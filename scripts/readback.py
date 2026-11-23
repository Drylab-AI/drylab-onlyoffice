"""Read back a saved xlsx/pptx from the harness (test only).
Usage: python readback.py <file> [cell-for-text] [cell-for-formula]"""
import sys, zipfile
p = sys.argv[1]
if p.endswith('.xlsx'):
    from openpyxl import load_workbook
    wb = load_workbook(p); ws = wb.worksheets[0]
    t, f = sys.argv[2], sys.argv[3]
    print({'sheets': wb.sheetnames, t: ws[t].value, f: ws[f].value, 'charts': sum(1 for n in zipfile.ZipFile(p).namelist() if n.startswith('xl/charts/chart'))})
else:
    from pptx import Presentation
    prs = Presentation(p)
    out = []
    for i, s in enumerate(prs.slides):
        txt = ' | '.join(sh.text_frame.text for sh in s.shapes if sh.has_text_frame)[:120]
        notes = s.notes_slide.notes_text_frame.text if s.has_notes_slide and s.notes_slide.notes_text_frame else ''
        out.append({'i': i + 1, 'text': txt, 'notes': notes[:80]})
    print({'slides': len(prs.slides), 'detail': out})
