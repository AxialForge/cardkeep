"""Printable sheet of fictional business cards for phone scan tests (SCAN-03..08).

Usage: python docs/_tools/make_test_cards.py "Documentation/0.6.2/CardKeep Test Cards Rev 1.0.pdf"
Letter portrait, 8 cards at real size (3.5 x 2 in) with cut lines. All names,
numbers (555) and domains (.example) are made up.
"""
import io
import sys

import qrcode
from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

W, H = 3.5 * inch, 2 * inch


def qr(data):
    buf = io.BytesIO()
    qrcode.make(data, border=1).save(buf, format="PNG")
    buf.seek(0)
    return ImageReader(buf)


def card(c, x, y, bg, fg, lines, accent=None, qr_data=None, label=""):
    c.setFillColor(HexColor(bg))
    c.rect(x, y, W, H, fill=1, stroke=0)
    if accent:
        c.setFillColor(HexColor(accent))
        c.rect(x, y, W, 0.08 * inch, fill=1, stroke=0)
    ty = y + H - 0.38 * inch
    for text, size, bold in lines:
        c.setFillColor(HexColor(fg))
        c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
        c.drawString(x + 0.22 * inch, ty, text)
        ty -= size + 4.5
    if qr_data:
        s = 0.95 * inch
        c.drawImage(qr(qr_data), x + W - s - 0.18 * inch, y + 0.22 * inch, s, s)
    # Cut line and test label outside the card.
    c.setStrokeColor(HexColor("#999999"))
    c.setDash(2, 2)
    c.rect(x, y, W, H, fill=0, stroke=1)
    c.setDash()
    c.setFillColor(HexColor("#666666"))
    c.setFont("Helvetica", 7)
    c.drawString(x, y - 9, label)


VCARD = (
    "BEGIN:VCARD\nVERSION:3.0\nN:Whitfield;Dana;;;\nFN:Dana Whitfield\nORG:Larkspur Analytics\n"
    "TITLE:Data Lead\nTEL;TYPE=CELL:+1 216 555 0148\nEMAIL:dana@larkspur.example\n"
    "URL:https://larkspur.example\nEND:VCARD"
)

CARDS = [
    dict(bg="#14213D", fg="#F5F1E6", accent="#E3A72F", label="1. Dark card, light text (SCAN-07)", lines=[
        ("Marisol Okafor", 15, True), ("Plant Manager", 9.5, False), ("Ironbridge Castings", 10, True),
        ("", 4, False), ("M  330 555 0114", 8.5, False), ("marisol@ironbridge.example", 8.5, False),
        ("ironbridge.example", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#1B1B1B", accent="#2E7D5B", qr_data=VCARD, label="2. QR code with a vCard (SCAN-08)", lines=[
        ("Dana Whitfield", 14, True), ("Data Lead", 9.5, False), ("Larkspur Analytics", 10, True),
        ("", 4, False), ("Scan the code", 8.5, False), ("for my details", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#1B1B1B", label="3. Middle initial (SCAN-06)", accent="#C4562E", lines=[
        ("Jordan R. Beckett", 14, True), ("Quality Engineer", 9.5, False), ("Halden Tooling Group", 10, True),
        ("", 4, False), ("T  440 555 0170", 8.5, False), ("M  440 555 0171", 8.5, False),
        ("jbeckett@halden.example", 8.5, False)]),
    dict(bg="#F4F4F4", fg="#111111", label="4. ALL CAPS, fax and extension (SCAN-06)", lines=[
        ("THEODORE VANCE", 14, True), ("SENIOR BUYER", 9.5, False), ("NORTHWIND FORGING INC.", 10, True),
        ("", 4, False), ("TEL 330 555 0190 EXT. 214", 8.5, False), ("FAX 330 555 0191", 8.5, False),
        ("T.VANCE@NORTHWIND.EXAMPLE", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#22303C", accent="#22303C", label="5. Two-sided: FRONT (SCAN-03)", lines=[
        ("Priya Natarajan", 14, True), ("Account Executive", 9.5, False), ("", 4, False),
        ("M  216 555 0133", 8.5, False), ("priya@brightline.example", 8.5, False)]),
    dict(bg="#22303C", fg="#FFFFFF", label="6. Two-sided: BACK (scan after 'Add the back side')", lines=[
        ("Brightline Medical Supply", 12, True), ("1200 Lakeview Pkwy, Suite 300", 8.5, False),
        ("Cleveland, OH 44114", 8.5, False), ("", 4, False), ("brightline.example", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#1B1B1B", accent="#6A4C93", qr_data="https://orbit.example/sam", label="7. QR code with a link (SCAN-08)", lines=[
        ("Sam Ellery", 14, True), ("Founder", 9.5, False), ("Orbit Studio", 10, True), ("", 4, False),
        ("sam@orbit.example", 8.5, False)]),
    dict(bg="#EAF1F8", fg="#3D5A80", label="8. Low contrast (hard case)", lines=[
        ("Lena Hartmann", 14, True), ("Purchasing Agent", 9.5, False), ("Cobalt Fasteners", 10, True),
        ("", 4, False), ("O  234 555 0122", 8.5, False), ("lena@cobalt.example", 8.5, False)]),
]


def main(out):
    c = canvas.Canvas(out, pagesize=letter)
    pw, ph = letter
    c.setFont("Helvetica-Bold", 13)
    c.drawString(0.6 * inch, ph - 0.55 * inch, "CardKeep test cards (fictional) - print at 100% / Actual size, cut on the dashed lines")
    gx = (pw - 2 * W - 0.4 * inch) / 2
    for i, d in enumerate(CARDS):
        col, row = i % 2, i // 2
        x = gx + col * (W + 0.4 * inch)
        y = ph - 0.9 * inch - (row + 1) * H - row * 0.38 * inch
        card(c, x, y, **d)
    c.save()
    print(out)


if __name__ == "__main__":
    main(sys.argv[1])
