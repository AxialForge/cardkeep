"""Render a Markdown doc to a portrait A4/Letter PDF via headless Edge.

Usage: python docs/_tools/build_doc_pdf.py docs/ROADMAP.md "Documentation/Card Organizer Roadmap Rev 1.0.pdf"
"""
import pathlib
import subprocess
import sys

import markdown

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

CSS = """
@page { size: Letter portrait; margin: 16mm 14mm 18mm 14mm;
  @bottom-center { content: counter(page) " / " counter(pages); font: 8pt 'Hanken Grotesk', sans-serif; color: #4A5568; } }
body { font: 9.5pt/1.45 'Hanken Grotesk', 'Segoe UI', sans-serif; color: #0E1A2B; }
h1 { font: 600 26pt 'Newsreader', Georgia, serif; margin: 0 0 4pt; border-bottom: 2pt solid #B08A4A; padding-bottom: 6pt; }
h2 { font: 600 17pt 'Newsreader', Georgia, serif; margin: 18pt 0 6pt; color: #0E1A2B; break-after: avoid; }
h3 { font: 600 12.5pt 'Newsreader', Georgia, serif; margin: 14pt 0 4pt; color: #7A5B22; break-after: avoid; }
h2 + h3 { margin-top: 6pt; }
p, li { margin: 3pt 0; }
code { font: 8.3pt Consolas, monospace; background: #F3F4F6; padding: 0 2pt; border-radius: 2pt; }
pre { background: #F3F4F6; border: 0.5pt solid #E2E5EA; padding: 6pt 8pt; font-size: 8pt; break-inside: avoid; white-space: pre-wrap; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 5pt 0 8pt; font-size: 8.4pt; }
th { background: #0E1A2B; color: #fff; text-align: left; padding: 3pt 5pt; font-weight: 600; }
td { border-bottom: 0.5pt solid #E2E5EA; padding: 3pt 5pt; vertical-align: top; }
tr { break-inside: avoid; }
td:first-child { white-space: nowrap; color: #7A5B22; font-weight: 600; }
hr { border: 0; break-after: page; }
img { max-height: 92mm; max-width: 48%; border: 0.5pt solid #E2E5EA; border-radius: 4pt; margin: 4pt 3pt; vertical-align: top; }
  p:has(> img) { text-align: center; }
p img + em, p > em:only-child { display: block; }
strong { color: #0E1A2B; }
.box { display: inline-block; width: 8pt; height: 8pt; border: 0.8pt solid #4A5568; border-radius: 1.5pt; vertical-align: -1pt; }
.done { background: #B08A4A; border-color: #B08A4A; }
.part { background: linear-gradient(135deg, #B08A4A 50%, #fff 50%); border-color: #B08A4A; }
"""


def main(src: str, out: str) -> None:
    src_p = pathlib.Path(src)
    html_body = markdown.markdown(src_p.read_text(encoding="utf-8"), extensions=["tables", "fenced_code"])
    # Status marks become printable tick boxes.
    html_body = (html_body.replace("[x]", '<span class="box done"></span>')
                 .replace("[~]", '<span class="box part"></span>')
                 .replace("[ ]", '<span class="box"></span>'))
    html = f"""<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Newsreader:wght@400;600&family=Hanken+Grotesk:wght@400;600&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>{html_body}</body></html>"""
    tmp = src_p.with_suffix(".print.html")
    tmp.write_text(html, encoding="utf-8")
    out_p = pathlib.Path(out).resolve()
    out_p.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([EDGE, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                    "--virtual-time-budget=8000", f"--print-to-pdf={out_p}", tmp.resolve().as_uri()],
                   check=True, capture_output=True)
    tmp.unlink()
    print(out_p)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
