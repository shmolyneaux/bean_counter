#!/usr/bin/env python3
"""
Parse an RBC Day-to-Day Banking account PDF statement using pdfplumber.

Uses word x-positions to distinguish Withdrawals from Deposits columns,
which cannot be determined from text alone.

Usage:
    python3 parse_rbc_savings_statement.py /path/to/statement.pdf
    python3 parse_rbc_savings_statement.py /path/to/statement.pdf > transactions.json
"""

import re
import sys
import json
import pdfplumber
from datetime import datetime
from collections import defaultdict

ROW_TOL = 3  # vertical tolerance (PDF units) for grouping words into one row

MONTHS = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
    'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
    'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
}

# Dates are like "23Feb" or "2Mar" — no space between day and month
DATE_RE   = re.compile(r'^(\d{1,2})([A-Z][a-z]{2})$')
AMOUNT_RE = re.compile(r'^[\d,]+\.\d{2}$')


def detect_col_boundaries(words: list[dict]) -> tuple[float, float]:
    """
    Return (wd_x, dep_x): the left-edge x of the Withdrawals and Deposits headers.
    The balance column is the rightmost and is detected implicitly (not needed directly).
    """
    wd = dep = None
    for w in words:
        t = w['text']
        if t.startswith('Withdrawals'):
            wd = w['x0']
        elif t.startswith('Deposits'):
            dep = w['x0']
    return (wd or 318.0), (dep or 423.0)


def group_into_rows(words: list[dict]) -> list[list[dict]]:
    if not words:
        return []
    sorted_words = sorted(words, key=lambda w: (w['top'], w['x0']))
    rows = [[sorted_words[0]]]
    current_top = sorted_words[0]['top']
    for word in sorted_words[1:]:
        if abs(word['top'] - current_top) <= ROW_TOL:
            rows[-1].append(word)
        else:
            rows.append([word])
            current_top = word['top']
    return rows


def parse_row(row: list[dict], wd_x: float, dep_x: float) -> dict:
    """
    Extract date, description, and transaction amounts from a row of words.

    Amount strategy: collect all amounts with their x-positions.
    The rightmost amount is always the running balance — ignore it.
    Classify each remaining amount as withdrawal (x < dep_x) or deposit (x >= dep_x).
    """
    desc_words = []
    amounts = []  # list of (x0, float_value)

    for w in sorted(row, key=lambda w: w['x0']):
        x, text = w['x0'], w['text']
        if x >= wd_x and AMOUNT_RE.match(text):
            amounts.append((x, float(text.replace(',', ''))))
        else:
            desc_words.append((x, text))

    # Drop rightmost amount (running balance)
    if len(amounts) > 1:
        amounts = amounts[:-1]

    # Split date from description
    date_token = None
    desc_parts = []
    for x, text in sorted(desc_words):
        if date_token is None and DATE_RE.match(text):
            date_token = text
        else:
            desc_parts.append(text)

    withdrawals = [v for x, v in amounts if x < dep_x]
    deposits    = [v for x, v in amounts if x >= dep_x]

    return {
        'date_token':  date_token,
        'description': ' '.join(desc_parts),
        'withdrawals': withdrawals,
        'deposits':    deposits,
    }


def extract_statement_year(text: str) -> int:
    m = re.search(r'to[A-Za-z]+\d+,(\d{4})', text)
    return int(m.group(1)) if m else datetime.now().year


def extract_end_month(text: str) -> int:
    m = re.search(r'to([A-Z][a-z]+)\d', text)
    return MONTHS.get(m.group(1)[:3], 12) if m else 12


def parse_date_token(token: str, year: int) -> str | None:
    m = DATE_RE.match(token)
    if not m:
        return None
    day, mon = int(m.group(1)), m.group(2)
    return datetime(year, MONTHS[mon], day).strftime('%Y-%m-%d')


def infer_year(month_num: int, end_month: int, statement_year: int) -> int:
    return statement_year - 1 if month_num > end_month else statement_year


def parse_pdf(pdf_path: str) -> list[dict]:
    transactions = []

    with pdfplumber.open(pdf_path) as pdf:
        first_text = (pdf.pages[0].extract_text() or '').replace('\n', ' ')
        statement_year = extract_statement_year(first_text)
        end_month = extract_end_month(first_text)

        current_date = None

        for page in pdf.pages:
            words = page.extract_words()
            wd_x, dep_x = detect_col_boundaries(words)
            rows = group_into_rows(words)

            for row in rows:
                r = parse_row(row, wd_x, dep_x)

                if not r['withdrawals'] and not r['deposits']:
                    continue

                if r['date_token']:
                    m = DATE_RE.match(r['date_token'])
                    year = infer_year(MONTHS[m.group(2)], end_month, statement_year)
                    current_date = parse_date_token(r['date_token'], year)

                if not current_date or not r['description']:
                    continue

                for v in r['withdrawals']:
                    transactions.append({
                        'date':        current_date,
                        'description': r['description'],
                        'amount':      -v,
                    })
                for v in r['deposits']:
                    transactions.append({
                        'date':        current_date,
                        'description': r['description'],
                        'amount':      v,
                    })

    return transactions


def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <path/to/statement.pdf>', file=sys.stderr)
        sys.exit(1)

    transactions = parse_pdf(sys.argv[1])
    print(json.dumps(transactions, indent=2))
    print(f'# Parsed {len(transactions)} transactions', file=sys.stderr)


if __name__ == '__main__':
    main()
