#!/usr/bin/env python3
"""
Parse bank/credit card PDF statements. Auto-detects format from first page text.

Supported formats:
  - CIBC Costco World Mastercard
  - RBC Rewards Visa
  - RBC Day-to-Day Banking (savings/chequing)

Usage:
    python3 parse_statement.py /path/to/statement.pdf
    python3 parse_statement.py /path/to/statement.pdf > transactions.json
"""

import re
import sys
import json
import pdfplumber
from datetime import datetime
from collections import defaultdict

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

ROW_TOL = 3  # vertical tolerance (PDF units) for grouping words into one row

MONTHS_TITLE = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
    'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
    'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
}
MONTHS_UPPER = {k.upper(): v for k, v in MONTHS_TITLE.items()}


def fmt_date(year: int, month: int, day: int) -> str:
    return datetime(year, month, day).strftime('%Y-%m-%d')


def infer_year(month_num: int, end_month: int, statement_year: int) -> int:
    return statement_year - 1 if month_num > end_month else statement_year


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


# ---------------------------------------------------------------------------
# Format detection
# ---------------------------------------------------------------------------

def detect_format(first_page_text: str) -> str:
    """Return one of: 'cibc_mastercard', 'rbc_visa', 'rbc_savings'."""
    t = first_page_text
    if 'CIBC' in t and 'Mastercard' in t:
        return 'cibc_mastercard'
    if 'RBC' in t and 'Visa' in t:
        return 'rbc_visa'
    if 'RBC' in t and ('Banking' in t or 'Withdrawals' in t):
        return 'rbc_savings'
    raise ValueError(f'Unrecognised statement format. First 200 chars:\n{t[:200]}')


# ---------------------------------------------------------------------------
# CIBC Costco World Mastercard
# ---------------------------------------------------------------------------

_CIBC_CATEGORIES = [
    'Transportation',
    'Restaurants',
    'Retail and Grocery',
    'Personal and Household Expenses',
    'Professional and Financial Services',
    'Hotel, Entertainment and Recreation',
    'Home and Office Improvement',
    'Health and Education',
]
_cibc_cat_pat = '|'.join(re.escape(c) for c in _CIBC_CATEGORIES)

_CIBC_CHARGE_RE = re.compile(
    r'^([A-Z][a-z]{2} \d{1,2})'
    r' ([A-Z][a-z]{2} \d{1,2})'
    r' (.+?)'
    r' (' + _cibc_cat_pat + r')'
    r' (-?[\d,]+\.\d{2})$'
)
_CIBC_PAYMENT_RE = re.compile(
    r'^([A-Z][a-z]{2} \d{1,2})'
    r' ([A-Z][a-z]{2} \d{1,2})'
    r' (PRE-AUTHORIZED PAYMENT\S*(?:\s+\S+)*?)'
    r' (-?[\d,]+\.\d{2})$'
)


def _cibc_parse_date(text: str, year: int) -> str:
    parts = text.split()
    return fmt_date(year, MONTHS_TITLE[parts[0]], int(parts[1]))


def _cibc_infer_year(date_str: str, end_month: int, statement_year: int) -> int:
    return infer_year(MONTHS_TITLE[date_str.split()[0]], end_month, statement_year)


def parse_cibc_mastercard(pdf: pdfplumber.PDF) -> list[dict]:
    first_text = pdf.pages[0].extract_text() or ''
    m = re.search(r'Statement Date\s+\w+ \d+,\s+(\d{4})', first_text)
    statement_year = int(m.group(1)) if m else datetime.now().year
    m = re.search(r'to\s+(\w+)\s+\d+,\s+\d{4}', first_text)
    end_month = MONTHS_TITLE.get((m.group(1) if m else 'Dec')[:3], 12)

    transactions = []
    for page in pdf.pages:
        for line in (page.extract_text() or '').splitlines():
            line = line.strip()
            m = _CIBC_CHARGE_RE.match(line)
            if m:
                trans, post, desc, category, amount_str = m.groups()
                year = _cibc_infer_year(trans, end_month, statement_year)
                transactions.append({
                    'trans_date':  _cibc_parse_date(trans, year),
                    'post_date':   _cibc_parse_date(post,  year),
                    'description': desc,
                    'category':    category,
                    'amount':      float(amount_str.replace(',', '')),
                })
                continue
            m = _CIBC_PAYMENT_RE.match(line)
            if m:
                trans, post, desc, amount_str = m.groups()
                year = _cibc_infer_year(trans, end_month, statement_year)
                transactions.append({
                    'trans_date':  _cibc_parse_date(trans, year),
                    'post_date':   _cibc_parse_date(post,  year),
                    'description': desc.strip(),
                    'category':    'Payment',
                    'amount':      -float(amount_str.replace(',', '')),
                })
    return transactions


# ---------------------------------------------------------------------------
# RBC Rewards Visa
# ---------------------------------------------------------------------------

_RBC_VISA_TX_RE = re.compile(
    r'^([A-Z]{3} \d{1,2})'
    r' ([A-Z]{3} \d{1,2})'
    r' (.+?)'
    r' (-?\$[\d,]+\.\d{2})'
    r'(?:\s.*)?$'
)


def _rbc_visa_parse_date(text: str, year: int) -> str:
    parts = text.split()
    return fmt_date(year, MONTHS_UPPER[parts[0]], int(parts[1]))


def _rbc_visa_infer_year(date_str: str, end_month: int, statement_year: int) -> int:
    return infer_year(MONTHS_UPPER[date_str.split()[0]], end_month, statement_year)


def parse_rbc_visa(pdf: pdfplumber.PDF) -> list[dict]:
    first_text = pdf.pages[0].extract_text() or ''
    m = re.search(r'STATEMENT FROM \w+ \d+ TO \w+ \d+,\s*(\d{4})', first_text)
    statement_year = int(m.group(1)) if m else datetime.now().year
    m = re.search(r'TO ([A-Z]{3}) \d+,', first_text)
    end_month = MONTHS_UPPER.get(m.group(1) if m else 'DEC', 12)

    transactions = []
    for page in pdf.pages:
        for line in (page.extract_text() or '').splitlines():
            m = _RBC_VISA_TX_RE.match(line.strip())
            if not m:
                continue
            trans, post, desc, amount_str = m.groups()
            year = _rbc_visa_infer_year(trans, end_month, statement_year)
            transactions.append({
                'trans_date':  _rbc_visa_parse_date(trans, year),
                'post_date':   _rbc_visa_parse_date(post,  year),
                'description': desc.strip(),
                'amount':      float(amount_str.replace('$', '').replace(',', '')),
            })
    return transactions


# ---------------------------------------------------------------------------
# RBC Day-to-Day Banking (savings / chequing)
# ---------------------------------------------------------------------------

_SAVINGS_DATE_RE   = re.compile(r'^(\d{1,2})([A-Z][a-z]{2})$')
_SAVINGS_AMOUNT_RE = re.compile(r'^[\d,]+\.\d{2}$')


def _savings_detect_cols(words: list[dict]) -> tuple[float, float]:
    wd = dep = None
    for w in words:
        t = w['text']
        if t.startswith('Withdrawals'):
            wd = w['x0']
        elif t.startswith('Deposits'):
            dep = w['x0']
    return (wd or 318.0), (dep or 423.0)


def _savings_parse_row(row: list[dict], wd_x: float, dep_x: float) -> dict:
    desc_words = []
    amounts = []
    for w in sorted(row, key=lambda w: w['x0']):
        x, text = w['x0'], w['text']
        if x >= wd_x and _SAVINGS_AMOUNT_RE.match(text):
            amounts.append((x, float(text.replace(',', ''))))
        else:
            desc_words.append((x, text))
    if len(amounts) > 1:
        amounts = amounts[:-1]  # drop rightmost (running balance)
    date_token = None
    desc_parts = []
    for x, text in desc_words:
        if date_token is None and _SAVINGS_DATE_RE.match(text):
            date_token = text
        else:
            desc_parts.append(text)
    return {
        'date_token':  date_token,
        'description': ' '.join(desc_parts),
        'withdrawals': [v for x, v in amounts if x < dep_x],
        'deposits':    [v for x, v in amounts if x >= dep_x],
    }


def parse_rbc_savings(pdf: pdfplumber.PDF) -> list[dict]:
    first_text = (pdf.pages[0].extract_text() or '').replace('\n', ' ')
    m = re.search(r'to[A-Za-z]+\d+,(\d{4})', first_text)
    statement_year = int(m.group(1)) if m else datetime.now().year
    m = re.search(r'to([A-Z][a-z]+)\d', first_text)
    end_month = MONTHS_TITLE.get((m.group(1) if m else 'Dec')[:3], 12)

    transactions = []
    current_date = None

    for page in pdf.pages:
        words = page.extract_words()
        wd_x, dep_x = _savings_detect_cols(words)
        for row in group_into_rows(words):
            r = _savings_parse_row(row, wd_x, dep_x)
            if not r['withdrawals'] and not r['deposits']:
                continue
            if r['date_token']:
                dm = _SAVINGS_DATE_RE.match(r['date_token'])
                month_num = MONTHS_TITLE[dm.group(2)]
                year = infer_year(month_num, end_month, statement_year)
                current_date = fmt_date(year, month_num, int(dm.group(1)))
            if not current_date or not r['description']:
                continue
            for v in r['withdrawals']:
                transactions.append({'date': current_date, 'description': r['description'], 'amount': -v})
            for v in r['deposits']:
                transactions.append({'date': current_date, 'description': r['description'], 'amount': v})
    return transactions


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def parse_pdf(pdf_path: str) -> list[dict]:
    with pdfplumber.open(pdf_path) as pdf:
        first_text = pdf.pages[0].extract_text() or ''
        fmt = detect_format(first_text)
        if fmt == 'cibc_mastercard':
            return parse_cibc_mastercard(pdf)
        if fmt == 'rbc_visa':
            return parse_rbc_visa(pdf)
        if fmt == 'rbc_savings':
            return parse_rbc_savings(pdf)


def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <path/to/statement.pdf>', file=sys.stderr)
        sys.exit(1)

    transactions = parse_pdf(sys.argv[1])
    print(json.dumps(transactions, indent=2))
    print(f'# Parsed {len(transactions)} transactions', file=sys.stderr)


if __name__ == '__main__':
    main()
