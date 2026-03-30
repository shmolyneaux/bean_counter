#!/usr/bin/env python3
"""
Parse an RBC Rewards Visa PDF statement using pdfplumber.

Usage:
    python3 parse_rbc_visa_statement.py /path/to/statement.pdf
    python3 parse_rbc_visa_statement.py /path/to/statement.pdf > transactions.json
"""

import re
import sys
import json
import pdfplumber
from datetime import datetime

MONTHS = {
    'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4,
    'MAY': 5, 'JUN': 6, 'JUL': 7, 'AUG': 8,
    'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
}

# Matches: "MMM DD  MMM DD  description  [$|-$]amount  [optional sidebar junk]"
TX_RE = re.compile(
    r'^([A-Z]{3} \d{1,2})'    # trans date  e.g. "FEB 13"
    r' ([A-Z]{3} \d{1,2})'    # post date   e.g. "FEB 16"
    r' (.+?)'                  # description (non-greedy)
    r' (-?\$[\d,]+\.\d{2})'   # amount, e.g. "$25.98" or "-$491.38"
    r'(?:\s.*)?$'              # ignore any trailing sidebar text
)


def parse_date(text: str, year: int) -> str:
    parts = text.split()
    return datetime(year, MONTHS[parts[0]], int(parts[1])).strftime('%Y-%m-%d')


def extract_statement_year(text: str) -> int:
    m = re.search(r'STATEMENT FROM \w+ \d+ TO \w+ \d+,\s*(\d{4})', text)
    return int(m.group(1)) if m else datetime.now().year


def extract_end_month(text: str) -> int:
    m = re.search(r'TO ([A-Z]{3}) \d+,', text)
    return MONTHS.get(m.group(1), 12) if m else 12


def infer_year(date_str: str, end_month: int, statement_year: int) -> int:
    month = MONTHS[date_str.split()[0]]
    return statement_year - 1 if month > end_month else statement_year


def parse_pdf(pdf_path: str) -> list[dict]:
    transactions = []

    with pdfplumber.open(pdf_path) as pdf:
        first_text = pdf.pages[0].extract_text() or ''
        statement_year = extract_statement_year(first_text)
        end_month = extract_end_month(first_text)

        for page in pdf.pages:
            for line in (page.extract_text() or '').splitlines():
                m = TX_RE.match(line.strip())
                if not m:
                    continue
                trans, post, desc, amount_str = m.groups()
                year = infer_year(trans, end_month, statement_year)
                amount = float(amount_str.replace('$', '').replace(',', ''))
                transactions.append({
                    'trans_date':  parse_date(trans, year),
                    'post_date':   parse_date(post,  year),
                    'description': desc.strip(),
                    'amount':      amount,
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
