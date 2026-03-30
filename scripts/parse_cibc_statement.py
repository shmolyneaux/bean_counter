#!/usr/bin/env python3
"""
Parse a CIBC Costco World Mastercard PDF statement using pdfplumber.

Usage:
    python3 parse_cibc_statement.py /path/to/onlineStatement.pdf
    python3 parse_cibc_statement.py /path/to/onlineStatement.pdf > transactions.csv
"""

import re
import sys
import json
import pdfplumber
from datetime import datetime

MONTHS = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
    'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
    'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
}

CATEGORIES = [
    'Transportation',
    'Restaurants',
    'Retail and Grocery',
    'Personal and Household Expenses',
    'Professional and Financial Services',
    'Hotel, Entertainment and Recreation',
    'Home and Office Improvement',
    'Health and Education',
]

_cat_pattern = '|'.join(re.escape(c) for c in CATEGORIES)

# Matches charge/credit lines: trans-date  post-date  description  category  amount
CHARGE_RE = re.compile(
    r'^([A-Z][a-z]{2} \d{1,2})'    # trans date
    r' ([A-Z][a-z]{2} \d{1,2})'    # post date
    r' (.+?)'                       # description
    r' (' + _cat_pattern + r')'    # known spend category
    r' (-?[\d,]+\.\d{2})$'         # amount
)

# Matches payment lines: date  date  description  amount (no category column)
PAYMENT_RE = re.compile(
    r'^([A-Z][a-z]{2} \d{1,2})'
    r' ([A-Z][a-z]{2} \d{1,2})'
    r' (PRE-AUTHORIZED PAYMENT\S*(?:\s+\S+)*?)'
    r' (-?[\d,]+\.\d{2})$'
)


def parse_date(text: str, year: int) -> str:
    parts = text.split()
    return datetime(year, MONTHS[parts[0]], int(parts[1])).strftime('%Y-%m-%d')


def extract_statement_year(text: str) -> int:
    m = re.search(r'Statement Date\s+\w+ \d+,\s+(\d{4})', text)
    return int(m.group(1)) if m else datetime.now().year


def extract_end_month(text: str) -> int:
    m = re.search(r'to\s+(\w+)\s+\d+,\s+\d{4}', text)
    return MONTHS.get(m.group(1)[:3], 12) if m else 12


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
                line = line.strip()

                m = CHARGE_RE.match(line)
                if m:
                    trans, post, desc, category, amount_str = m.groups()
                    year = infer_year(trans, end_month, statement_year)
                    transactions.append({
                        'trans_date':  parse_date(trans, year),
                        'post_date':   parse_date(post,  year),
                        'description': desc,
                        'category':    category,
                        'amount':      float(amount_str.replace(',', '')),
                    })
                    continue

                m = PAYMENT_RE.match(line)
                if m:
                    trans, post, desc, amount_str = m.groups()
                    year = infer_year(trans, end_month, statement_year)
                    transactions.append({
                        'trans_date':  parse_date(trans, year),
                        'post_date':   parse_date(post,  year),
                        'description': desc.strip(),
                        'category':    'Payment',
                        'amount':      -float(amount_str.replace(',', '')),
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
