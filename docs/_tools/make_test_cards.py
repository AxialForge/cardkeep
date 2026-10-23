"""Printable sheet of fictional business cards for phone scan tests (SCAN-03..08).

Usage: python docs/_tools/make_test_cards.py "Documentation/0.7.0/CardKeep Test Cards 0.7.0 Rev 1.0.pdf" 0.7.0
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


# 0.7.0: places (no person on the card) and the cases from the owner's real cards.
CARDS_070 = [
    dict(bg="#FFF8EC", fg="#3B2A1A", accent="#C4562E", label="1. Store, no person (place: store)", lines=[
        ("Lakeside Hardware", 15, True), ("Tools - Paint - Keys cut while you wait", 8.5, False), ("", 4, False),
        ("412 Lakeshore Blvd, Willoughby, OH 44094", 8.5, False), ("Mon-Sat 8am-7pm  Sun 10am-4pm", 8.5, False),
        ("440 555 0161", 8.5, False), ("lakesidehardware.example", 8.5, False)]),
    dict(bg="#1F2A24", fg="#F3EBDD", accent="#D9A441", label="2. Restaurant, no person (place: restaurant)", lines=[
        ("The Copper Kettle Cafe", 14, True), ("Breakfast - Lunch - Catering", 9, False), ("", 4, False),
        ("Open daily 7am-3pm", 8.5, False), ("88 Main St, Chagrin Falls, OH 44022", 8.5, False),
        ("Order online: copperkettle.example", 8.5, False), ("440 555 0177", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#1B1B1B", accent="#2E5E8C", qr_data="https://reliablefasteners.example/catalog",
         label="3. Vendor, no person, QR link (place: vendor)", lines=[
        ("Reliable Fastener Supply", 12.5, True), ("Bolts, nuts, studs - same-day shipping", 8, False), ("", 4, False),
        ("Visit us: 2200 Industrial Pkwy", 8, False), ("Streetsboro, OH 44241", 8, False),
        ("Sales 330 555 0198", 8, False), ("sales@reliablefasteners.example", 8, False)]),
    dict(bg="#F2F2F2", fg="#151515", accent="#B3261E", label="4. Service, no person (place: service)", lines=[
        ("MIDTOWN AUTO REPAIR", 13, True), ("BRAKES - TIRES - OIL CHANGE - INSPECTIONS", 7.5, False), ("", 4, False),
        ("Mon-Fri 7:30-6:00", 8.5, False), ("1450 E 55th St, Cleveland, OH 44103", 8.5, False),
        ("216 555 0112", 8.5, False), ("midtownauto.example", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#2B2F6B", accent="#2B2F6B", label="5. Dr. + credential + two-line company (person)", lines=[
        ("BRIGHTWATER", 15, True), ("Family Dental", 11, True), ("", 4, False),
        ("Dr. Elena M Kowalczyk DDS", 9, False), ("21 Ridge Rd, Hudson, OH 44236", 8.5, False),
        ("330 555 0150", 8.5, False), ("dr.k@brightwaterdental.example", 8.5, False)]),
    dict(bg="#111111", fg="#F0F0F0", accent="#C0392B", label="6. NAME, TITLE on one line + .games + slogan (person)", lines=[
        ("MARCUS VALE, DIRECTOR OF SALES", 10.5, True), ("MARCUS@IRONDICE.GAMES", 8.5, False),
        ("CELL: 614.555.0139", 8.5, False), ("", 4, False), ("WWW.IRONDICE.GAMES", 11, True),
        ("MAKERS OF TABLETOP DICE, MAPS AND MORE!", 7.5, False)]),
    dict(bg="#FFFFFF", fg="#1B1B1B", accent="#5B8C3A", label="7. Person at a shop (person, not a place)", lines=[
        ("Rosa Delgado", 14, True), ("Store Manager", 9.5, False), ("Greenfield Garden Center", 10, True),
        ("", 4, False), ("Mon-Sun 9-6", 8.5, False), ("C 440 555 0185", 8.5, False), ("rosa@greenfield.example", 8.5, False)]),
    dict(bg="#FFFFFF", fg="#1B1B1B", qr_data="https://freebies.example/downloads",
         label="8. Back of card 6 (scan after 'Add the back side': notes only)", lines=[
        ("FREE DOWNLOADS!", 14, True), ("GET FREE MAPS AND PRINTABLE", 8, False), ("CHARACTER SHEETS AND MORE!", 8, False)]),
]

SETS = {"0.6.2": CARDS, "0.7.0": CARDS_070}


def main(out, which="0.6.2"):
    cards = SETS[which]
    c = canvas.Canvas(out, pagesize=letter)
    pw, ph = letter
    c.setFont("Helvetica-Bold", 13)
    c.drawString(0.6 * inch, ph - 0.55 * inch, "CardKeep test cards (fictional) - print at 100% / Actual size, cut on the dashed lines")
    gx = (pw - 2 * W - 0.4 * inch) / 2
    for i, d in enumerate(cards):
        col, row = i % 2, i // 2
        x = gx + col * (W + 0.4 * inch)
        y = ph - 0.9 * inch - (row + 1) * H - row * 0.38 * inch
        card(c, x, y, **d)
    c.save()
    print(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "0.6.2")
