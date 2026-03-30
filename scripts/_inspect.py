import pdfplumber
with pdfplumber.open('/mnt/y/Downloads/Savings Statement-5741 2026-03-17.pdf') as pdf:
    page = pdf.pages[0]
    words = page.extract_words()
    in_activity = False
    for w in words:
        if w['text'] == 'OpeningBalance':
            in_activity = True
        if in_activity:
            print("x0=%-6.1f  %s" % (w['x0'], w['text']))
