import os
P = '/tmp/claude-0/-home-claude/10b4d30e-3851-5632-943c-85f4d9ba7ea8/scratchpad/card-ui-exec/project/'
SER = "font-family:'Newsreader',Georgia,serif"

HEAD = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>@T@</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@400;500;600;700&family=Newsreader:wght@500;600&display=swap">
<style>
body{margin:0}
a{color:inherit}
button{font-family:inherit}
input,select,textarea{font-family:inherit}
</style>
</helmet>
<div style="width: 390px; height: 844px; position: relative; overflow: hidden; box-sizing: border-box; display: flex; flex-direction: column; background: #F3F4F6; color: #0E1A2B; font-family: 'Hanken Grotesk', system-ui, sans-serif">
'''
TAIL = '''
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{}'>
@S@
</script>
</body>
</html>
'''
METHODS = '''  gs(k, d) { const v = this.state && this.state[k]; return v === undefined ? d : v; }
  sv(keys, cur, sk) {
    const o = {};
    keys.forEach((k) => {
      const on = cur === k;
      const K = k[0].toUpperCase() + k.slice(1);
      o['on' + K] = on;
      o['bg' + K] = on ? '#FFFFFF' : 'transparent';
      o['fg' + K] = on ? '#0E1A2B' : '#4A5568';
      o['sh' + K] = on ? '0 1px 3px rgba(14,26,43,0.16)' : 'none';
      o['pick' + K] = () => this.setState({ [sk]: k });
    });
    return o;
  }
  tg(o, id, on) {
    const I = id[0].toUpperCase() + id.slice(1);
    o[id + 'On'] = on;
    o[id + 'Bg'] = on ? '#0E1A2B' : '#8793A5';
    o[id + 'Left'] = on ? '23px' : '3px';
    o['toggle' + I] = () => this.setState({ [id]: !on });
  }
  qr(seed) {
    const n = 25; let s = seed; let d = '';
    const rnd = () => { s = (s * 48271) % 2147483647; return s / 2147483647; };
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      const tl = x < 7 && y < 7, tr = x >= n - 7 && y < 7, bl = x < 7 && y >= n - 7;
      let on;
      if (tl || tr || bl) {
        const fx = x < 7 ? x : x - (n - 7), fy = y < 7 ? y : y - (n - 7);
        on = fx === 0 || fx === 6 || fy === 0 || fy === 6 || (fx >= 2 && fx <= 4 && fy >= 2 && fy <= 4);
      } else on = rnd() > 0.52;
      if (on) d += 'M' + x + ' ' + y + 'h1v1h-1z';
    }
    return d;
  }
'''


def script(render_body):
    return 'class Component extends DCLogic {\n' + METHODS + '  renderVals() {\n' + render_body + '\n  }\n}'


EMPTY = script('    return {};')


def w(name, title, body, scr=None):
    s = HEAD.replace('@T@', title) + body + TAIL.replace('@S@', scr or EMPTY)
    open(P + name, 'w').write(s)


# ---------- html helpers ----------
def svg(d, size=20, sw='2', fill='none', stroke='currentColor'):
    return ('<svg width="' + str(size) + '" height="' + str(size) + '" viewBox="0 0 24 24" fill="' + fill + '" stroke="' + stroke +
            '" stroke-width="' + sw + '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + d + '"/></svg>')

BACK = 'M15 5l-7 7 7 7'
MENU = 'M4 7h16M4 12h16M4 17h16'
CHEV = 'M9 5l7 7-7 7'
PLUS = 'M12 5v14M5 12h14'
GLOBE = 'M12 3a9 9 0 100 18 9 9 0 000-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18'
PHONE = 'M5 4h4l2 5-2.500 1.500a11 11 0 005 5L15 13l5 2v4a2 2 0 01-2 2A15 15 0 013 6a2 2 0 012-2z'
MAIL = 'M3 7a2 2 0 012-2h14a2 2 0 012 2v10a2 2 0 01-2 2H5a2 2 0 01-2-2zM3 7l9 6 9-6'
CHECK = 'M5 12l5 5 9-10'
LOCK = 'M7 11V8a5 5 0 0110 0v3M6 11h12v9H6z'

NAVY = ('#E8ECF3', '#0E1A2B'); AMB = ('#FBF1DC', '#7A4E0B'); BRASS = ('#F3E9D4', '#6B4E17')
HOT = ('#F8E1DD', '#8C2F1F'); COLD = ('#E1EAF5', '#1F4A78')


def chip(t, c):
    return '<span style="flex:none;font-size:11px;font-weight:700;border-radius:10px;padding:3px 9px;background:' + c[0] + ';color:' + c[1] + '">' + t + '</span>'


def avatar(ini, size=42, bg='#E8ECF3', fg='#0E1A2B', extra=''):
    return ('<div style="width:' + str(size) + 'px;height:' + str(size) + 'px;border-radius:' + str(size // 2) + 'px;background:' + bg + ';color:' + fg +
            ';display:flex;align-items:center;justify-content:center;' + SER + ';font-size:' + str(int(size * 0.4)) + 'px;font-weight:600;flex:none;' + extra + '">' + ini + '</div>')


def circle_btn(href, d, label):
    return ('<a href="' + href + '" aria-label="' + label + '" style="width:44px;height:44px;border-radius:22px;background:#FFFFFF;border:1px solid #E2E5EA;'
            'display:flex;align-items:center;justify-content:center;color:#0E1A2B;text-decoration:none;flex:none">' + svg(d) + '</a>')


def header(title, back=None, sub=None, right=''):
    left = circle_btn(back, BACK, 'Back') if back else circle_btn('Menu.dc.html', MENU, 'Open menu')
    h = '<div style="flex:none;padding:14px 16px 6px 16px"><div style="display:flex;align-items:center;gap:10px">' + left + '<div style="flex:1"></div>' + right + '</div>'
    h += '<h1 style="margin:10px 4px 0 4px;' + SER + ';font-size:32px;font-weight:600;line-height:1.1;letter-spacing:-0.01em">' + title + '</h1>'
    if sub:
        h += '<div style="margin:4px 4px 0 4px;font-size:14px;color:#4A5568">' + sub + '</div>'
    return h + '</div>'


SC = '<div style="flex:1;min-height:0;overflow-y:auto;padding:8px 16px 24px 16px">'
ENDSC = '</div>'


def bar(inner):
    return '<div style="flex:none;display:flex;gap:10px;padding:12px 16px 22px 16px;background:#FFFFFF;border-top:1px solid #E2E5EA">' + inner + '</div>'


def bprimary(label, href, flex='1.5'):
    return ('<a href="' + href + '" style="flex:' + flex + ';height:52px;border-radius:14px;background:#0E1A2B;color:#FFFFFF;font-size:16px;font-weight:600;text-decoration:none;'
            'display:flex;align-items:center;justify-content:center">' + label + '</a>')


def boutline(label, href, flex='1'):
    return ('<a href="' + href + '" style="flex:' + flex + ';height:52px;border-radius:14px;border:1.5px solid #0E1A2B;background:#FFFFFF;color:#0E1A2B;font-size:16px;font-weight:600;text-decoration:none;'
            'display:flex;align-items:center;justify-content:center">' + label + '</a>')


def ext(url, label, flex='1', h=52):
    return ('<a href="' + url + '" target="_blank" rel="noopener" style="flex:' + flex + ';height:' + str(h) + 'px;border-radius:14px;border:1.5px solid #0E1A2B;background:#FFFFFF;color:#0E1A2B;font-size:15px;font-weight:600;'
            'text-decoration:none;display:flex;align-items:center;justify-content:center;gap:8px">' + svg(GLOBE, 18) + label + '</a>')


def card(inner, pad='16px', mt=12):
    return '<div style="margin-top:' + str(mt) + 'px;padding:' + pad + ';border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA">' + inner + '</div>'


def lab(t):
    return '<div style="font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22;margin-bottom:8px">' + t + '</div>'


LISTOPEN = '<div style="margin-top:12px;border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden">'


def seg(keys):
    out = '<div style="display:flex;padding:3px;border-radius:12px;background:#E6E9EE">'
    for k, l, f in keys:
        K = k[0].upper() + k[1:]
        out += ('<button onClick="{{ pick' + K + ' }}" aria-pressed="{{ on' + K + ' }}" style="flex:' + f + ';height:40px;border:0;border-radius:10px;font-size:13px;font-weight:600;cursor:pointer;'
                'background:{{ bg' + K + ' }};color:{{ fg' + K + ' }};box-shadow:{{ sh' + K + ' }}">' + l + '</button>')
    return out + '</div>'


def switch(id):
    I = id[0].upper() + id[1:]
    return ('<button onClick="{{ toggle' + I + ' }}" aria-pressed="{{ ' + id + 'On }}" aria-label="' + id + '" style="width:52px;height:32px;border:0;border-radius:16px;cursor:pointer;position:relative;flex:none;background:{{ ' + id + 'Bg }}">'
            '<span style="position:absolute;top:3px;left:{{ ' + id + 'Left }};width:26px;height:26px;border-radius:13px;background:#FFFFFF;box-shadow:0 1px 3px rgba(0,0,0,0.3)"></span></button>')


def trow(title, sub, id, last=False):
    return ('<div style="display:flex;align-items:center;gap:12px;min-height:64px;padding:6px 0;' + ('' if last else 'border-bottom:1px solid #EDEFF3;') + '"><div style="flex:1"><div style="font-size:15px;font-weight:600">' + title + '</div>'
            + ('<div style="font-size:12px;color:#4A5568;margin-top:2px">' + sub + '</div>' if sub else '') + '</div>' + switch(id) + '</div>')


def inp(label, val, id, type='text', flex='1'):
    return ('<div style="flex:' + flex + ';min-width:0"><label for="' + id + '" style="display:block;font-size:12px;font-weight:600;color:#4A5568;margin-bottom:5px">' + label + '</label>'
            '<input id="' + id + '" type="' + type + '" value="' + val + '" style="width:100%;height:48px;box-sizing:border-box;border:1px solid #D5DAE1;border-radius:12px;padding:0 14px;font-size:16px;background:#FFFFFF;color:#0E1A2B"></div>')


def pair(*items):
    return '<div style="display:flex;gap:10px;margin-top:14px">' + ''.join(items) + '</div>'


def crow(href, ini, name, c, l1, l2, abg='#E8ECF3'):
    return ('<a href="' + href + '" style="display:flex;align-items:center;gap:12px;min-height:84px;padding:10px 14px;box-sizing:border-box;text-decoration:none;color:#0E1A2B;border-bottom:1px solid #EDEFF3">'
            + avatar(ini, 44, abg) + '<div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:8px"><span style="font-size:15px;font-weight:600">' + name + '</span>' + chip(c[0], c[1]) + '</div>'
            '<div style="font-size:13px;margin-top:3px">' + l1 + '</div><div style="font-size:12px;color:#4A5568;margin-top:2px">' + l2 + '</div></div>'
            '<span style="color:#4A5568;flex:none">' + svg(CHEV, 16, '2.4') + '</span></a>')


def tl(items):
    out = ''
    for i, (color, t, s) in enumerate(items):
        last = i == len(items) - 1
        out += ('<div style="position:relative;margin-left:6px;padding-left:22px;padding-bottom:' + ('0' if last else '18px') + ';border-left:2px solid ' + ('transparent' if last else '#E2E5EA') + '">'
                '<span style="position:absolute;left:-7px;top:2px;width:12px;height:12px;border-radius:6px;background:' + color + '"></span>'
                '<div style="font-size:15px;font-weight:600">' + t + '</div><div style="font-size:12px;color:#4A5568;margin-top:2px">' + s + '</div></div>')
    return out


def minicard(company, name, title, lines, w_='100%'):
    return ('<div style="width:' + w_ + ';aspect-ratio:1.75;box-sizing:border-box;border-radius:8px;background:#FAFAF8;border:1px solid #E2E5EA;box-shadow:0 8px 20px rgba(14,26,43,0.12);padding:16px 18px;display:flex;flex-direction:column;justify-content:space-between">'
            '<div style="display:flex;align-items:center;gap:8px"><span style="width:18px;height:18px;background:#0E1A2B;border-radius:4px;display:block"></span><span style="font-size:11px;font-weight:700;letter-spacing:0.18em">' + company + '</span></div>'
            '<div><div style="' + SER + ';font-size:18px;font-weight:600">' + name + '</div><div style="font-size:11px;color:#4A5568;margin-bottom:6px">' + title + '</div>'
            '<div style="font-size:10.5px;color:#4A5568;line-height:1.55">' + lines + '</div></div></div>')


# =====================================================================
# CAREER (list)
# =====================================================================
body = header('Career moves', sub='People you track · 3 need review') + SC
body += card(lab('HOW TRACKING WORKS') + '<div style="font-size:14px;line-height:1.5;color:#0E1A2B">Nothing runs in the background. Changes come from new card scans, bounced emails you flag, and what you record yourself. Tap <b>Check on web</b> to look someone up in your default browser.</div>', '14px 16px', 4)
body += '<div style="margin-top:14px">' + seg([('review', 'Needs review 3', '1.4'), ('watch', 'Watching 24', '1.1'), ('retired', 'Retired 5', '1')]) + '</div>'
body += '<sc-if value="{{ showReview }}" hint-placeholder-val="{{ true }}">' + LISTOPEN
body += crow('JobChange.dc.html', 'MO', 'Marcus Oyelaran', ('MOVED', NAVY), 'Brightline Logistics to Corvane Freight', 'New card scanned Oct 17 · VP, Network Strategy')
body += crow('JobChange.dc.html', 'TA', 'Tomás Aguirre', ('POSSIBLE', AMB), 'Calder Hydraulics, email bounced', 'Flagged Oct 16 · no new card yet')
body += crow('Retired.dc.html', 'GP', 'Gary Pruitt', ('RETIRED', AMB), 'Purchasing Manager, Northgate Fasteners', 'Confirm replacement: Renata Okafor', '#EDEFF3')
body += '</div></sc-if>'
body += '<sc-if value="{{ showWatch }}" hint-placeholder-val="{{ false }}">' + LISTOPEN
for ini, n, l1, l2 in [('PN', 'Priya Nambiar', 'Director of Procurement · Halden Tooling Group', 'Confirmed Oct 7, 2026'),
                       ('EV', 'Elena Voss', 'Chief Commercial Officer · Northgate Fasteners', 'Confirmed Oct 6, 2026'),
                       ('HW', 'Hannah Whitcomb', 'Head of Purchasing · Ironbridge Steel', 'Confirmed Oct 7, 2026'),
                       ('WZ', 'Wen Zhao', 'Regional Sales Director · Calder Hydraulics', 'Confirmed Oct 8, 2026'),
                       ('DK', 'Dmitri Kowalczyk', 'General Manager · Halden Tooling Group', 'Confirmed Oct 7, 2026')]:
    body += crow('Detail.dc.html', ini, n, ('CURRENT', NAVY), l1, l2)
body += '<div style="padding:12px 16px;font-size:12px;color:#4A5568">Showing 5 of 24 tracked people.</div></div></sc-if>'
body += '<sc-if value="{{ showRetired }}" hint-placeholder-val="{{ false }}">' + LISTOPEN
body += crow('Retired.dc.html', 'GP', 'Gary Pruitt', ('RETIRED', AMB), 'Purchasing Manager · Northgate Fasteners', 'Replaced by Renata Okafor', '#EDEFF3')
body += crow('Detail.dc.html', 'WH', 'Walt Hendricks', ('RETIRED', AMB), 'Plant Buyer · Ironbridge Steel', 'Replaced by Hannah Whitcomb', '#EDEFF3')
body += crow('Detail.dc.html', 'LC', 'Linda Crowe', ('RETIRED', AMB), 'Operations Director · Brightline Logistics', 'No replacement recorded yet', '#EDEFF3')
body += '<div style="padding:12px 16px;font-size:12px;color:#4A5568">Showing 3 of 5 retired contacts.</div></div></sc-if>'
body += ENDSC
w('Career.dc.html', 'Career moves', body, script("""    const t = this.gs('tab', 'review');
    return Object.assign({ showReview: t === 'review', showWatch: t === 'watch', showRetired: t === 'retired' }, this.sv(['review', 'watch', 'retired'], t, 'tab'));"""))

# =====================================================================
# JOB CHANGE (resolve)
# =====================================================================
def cmp_row(label, a, b, changed):
    bcell = ('<div style="flex:1;min-width:0;padding:8px 10px;border-radius:10px;background:#FBF1DC;font-size:13px;font-weight:600;word-break:break-all">' + b + '</div>') if changed else \
            '<div style="flex:1;min-width:0;padding:8px 10px;font-size:13px;color:#4A5568">Same</div>'
    return ('<div style="display:flex;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid #EDEFF3"><div style="width:58px;flex:none;font-size:12px;color:#4A5568">' + label + '</div>'
            '<div style="flex:1;min-width:0;padding:8px 10px;font-size:13px;word-break:break-all">' + a + '</div>' + bcell + '</div>')


body = header('Possible job change', back='Career.dc.html', sub='A new scan matches a saved contact') + SC
body += card('<div style="display:flex;align-items:center;gap:12px">' + avatar('MO', 52, '#0E1A2B', '#FFFFFF') + '<div><div style="' + SER + ';font-size:22px;font-weight:600">Marcus Oyelaran</div>'
             '<div style="font-size:13px;color:#4A5568">Matched on mobile number · 98% confidence</div></div></div>', '14px 16px', 6)
body += card('<div style="display:flex;gap:8px;padding-bottom:8px;border-bottom:1px solid #E2E5EA"><div style="width:58px;flex:none"></div><div style="flex:1;font-size:12px;font-weight:700;letter-spacing:0.06em;color:#7A5B22;padding-left:10px">SAVED</div>'
             '<div style="flex:1;font-size:12px;font-weight:700;letter-spacing:0.06em;color:#7A5B22;padding-left:10px">NEW CARD</div></div>'
             + cmp_row('Company', 'Brightline Logistics', 'Corvane Freight', True)
             + cmp_row('Title', 'VP, Regional Operations', 'VP, Network Strategy', True)
             + cmp_row('Email', 'm.oyelaran@brightline.example', 'm.oyelaran@corvane.example', True)
             + cmp_row('Mobile', '+1 216 555 0173', '', False)
             + cmp_row('Office', '+1 216 555 0120', '+1 216 555 0194', True), '12px 12px 6px 12px', 12)
body += '<div style="margin:16px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">WHAT SHOULD HAPPEN</div>'
body += '<sc-for list="{{ opts }}" as="o" hint-placeholder-count="3">'
body += ('<button onClick="{{ o.pick }}" aria-pressed="{{ o.on }}" style="display:flex;align-items:flex-start;gap:12px;width:100%;text-align:left;margin-bottom:8px;padding:14px;border-radius:16px;background:{{ o.bg }};border:1.5px solid {{ o.bd }};cursor:pointer;color:#0E1A2B">'
         '<span style="width:22px;height:22px;border-radius:11px;box-sizing:border-box;border:2px solid {{ o.bd }};background:{{ o.dot }};flex:none;margin-top:1px"></span>'
         '<span style="flex:1"><span style="display:block;font-size:15px;font-weight:600">{{ o.title }}</span><span style="display:block;font-size:13px;color:#4A5568;margin-top:3px;line-height:1.4">{{ o.desc }}</span></span></button>')
body += '</sc-for>'
body += card(trow('Keep old email as former', 'Brightline address stays on file, marked inactive.', 'keepOld', True), '4px 16px', 4)
body += '<a href="Main.dc.html" style="display:flex;align-items:center;gap:12px;margin-top:12px;min-height:64px;padding:8px 16px;border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;text-decoration:none;color:#0E1A2B"><div style="flex:1"><div style="font-size:15px;font-weight:600">Who took over at Brightline Logistics?</div><div style="font-size:12px;color:#4A5568;margin-top:2px">Link a replacement contact (optional)</div></div><span style="color:#4A5568">' + svg(CHEV, 16, '2.4') + '</span></a>'
body += '<div style="margin-top:12px;display:flex">' + ext('https://www.google.com/search?q=Marcus+Oyelaran+Corvane+Freight', 'Check on web', '1', 48) + '</div>'
body += '<div style="margin:6px 4px 0 4px;font-size:12px;color:#4A5568">Opens in your default browser. Nothing is fetched automatically.</div>'
body += ENDSC + bar(boutline('Dismiss', 'Career.dc.html') + bprimary('Apply', 'Career.dc.html'))
w('JobChange.dc.html', 'Possible job change', body, script("""    const c = this.gs('choice', 'new');
    const defs = [
      { k: 'new', title: 'Add as new role, keep history', desc: 'Corvane Freight becomes current. Brightline moves to previous roles. Recommended.' },
      { k: 'replace', title: 'Replace old details', desc: 'Overwrite company, title, and email. No history kept.' },
      { k: 'diff', title: 'Different person', desc: 'Keep both contacts. Dismiss this match.' }
    ];
    const opts = defs.map((d) => ({
      title: d.title, desc: d.desc, on: c === d.k,
      bg: c === d.k ? '#E8ECF3' : '#FFFFFF', bd: c === d.k ? '#0E1A2B' : '#D5DAE1', dot: c === d.k ? '#0E1A2B' : '#FFFFFF',
      pick: () => this.setState({ choice: d.k })
    }));
    const o = { opts };
    this.tg(o, 'keepOld', this.gs('keepOld', true));
    return o;"""))

# =====================================================================
# RETIRED (with replacement)
# =====================================================================
body = header('Gary Pruitt', back='Career.dc.html', sub='Purchasing Manager · Northgate Fasteners',
              right=chip('RETIRED', AMB)) + SC
body += card('<div style="display:flex;align-items:center;gap:12px">' + avatar('GP', 52, '#EDEFF3') + '<div style="flex:1"><div style="font-size:15px;font-weight:600">Retired Sep 30, 2026</div>'
             '<div style="font-size:13px;color:#4A5568;margin-top:2px">Phone and email are no longer monitored.</div></div></div>', '14px 16px', 6)
rep = lab('REPLACED BY')
rep += '<div style="display:flex;align-items:center;gap:12px;margin-bottom:14px">' + avatar('RO', 52, '#0E1A2B', '#FFFFFF') + '<div><div style="' + SER + ';font-size:22px;font-weight:600;line-height:1.15">Renata Okafor</div>'
rep += '<div style="font-size:14px;color:#4A5568">Senior Purchasing Manager</div><div style="font-size:13px;color:#7A5B22;font-weight:600">Northgate Fasteners</div></div></div>'
rep += minicard('NORTHGATE FASTENERS', 'Renata Okafor', 'Senior Purchasing Manager', 'M +1 330 555 0167 &nbsp;·&nbsp; O +1 330 555 0140<br>r.okafor@northgatefasteners.example<br>1180 Commerce Dr, Barberton, OH 44203')
rep += ('<div style="display:flex;gap:10px;margin-top:14px">'
        '<a href="tel:+13305550167" style="flex:1;height:48px;border-radius:12px;background:#0E1A2B;color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px">' + svg(PHONE, 18) + 'Call</a>'
        '<a href="mailto:r.okafor@northgatefasteners.example" style="flex:1;height:48px;border-radius:12px;background:#0E1A2B;color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px">' + svg(MAIL, 18) + 'Email</a>'
        '<a href="Detail.dc.html" style="flex:1;height:48px;border-radius:12px;border:1.5px solid #D5DAE1;background:#FFFFFF;color:#0E1A2B;text-decoration:none;font-size:14px;font-weight:600;display:flex;align-items:center;justify-content:center">Open</a></div>')
rep += '<div style="margin-top:10px;font-size:12px;color:#4A5568">Card scanned Oct 8 at Fabricators Expo 2026</div>'
body += card(rep, '16px', 12)
body += '<a href="Followups.dc.html" style="display:flex;align-items:center;gap:12px;margin-top:12px;min-height:64px;padding:8px 16px;border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;text-decoration:none;color:#0E1A2B"><div style="flex:1"><div style="font-size:15px;font-weight:600">Move 2 open follow-ups to Renata</div><div style="font-size:12px;color:#4A5568;margin-top:2px">Quote request and plant visit</div></div><span style="color:#4A5568">' + svg(CHEV, 16, '2.4') + '</span></a>'
body += card(lab('PREVIOUS CONTACT INFO') + '<div style="font-size:15px;color:#5B6676;text-decoration:line-through;line-height:1.7">+1 (330) 555-0151<br>g.pruitt@northgatefasteners.example</div>', '14px 16px', 12)
body += card(lab('CAREER TIMELINE') + tl([('#B08A4A', 'Purchasing Manager, Northgate Fasteners', '2008 to Sep 2026 · Retired'),
                                          ('#8793A5', 'Purchasing Agent, Ironbridge Steel', '2002 to 2008'),
                                          ('#0E1A2B', 'Card first scanned', 'Precision Machining Expo, Jun 2026')]), '16px', 12)
body += '<div style="margin-top:12px;display:flex">' + ext('https://www.google.com/search?q=Gary+Pruitt+Northgate+Fasteners+retirement', 'Check on web', '1', 48) + '</div>'
body += '<div style="margin:6px 4px 0 4px;font-size:12px;color:#4A5568">Opens in your default browser.</div>'
body += ENDSC + bar(boutline('Mark active again', 'Career.dc.html') + bprimary('Confirm replacement', 'Career.dc.html'))
w('Retired.dc.html', 'Retired contact', body)

# =====================================================================
# DUPLICATES
# =====================================================================
body = header('Duplicates', sub='7 possible matches') + SC
body += '<div style="margin-top:6px">' + seg([('all', 'All 7', '1'), ('exact', 'Exact 3', '1'), ('similar', 'Similar 4', '1')]) + '</div>'
body += '<div style="margin-top:12px;border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden">'
body += '<sc-for list="{{ rows }}" as="r" hint-placeholder-count="5">'
body += ('<a href="Merge.dc.html" style="display:flex;align-items:center;gap:12px;min-height:76px;padding:10px 14px;box-sizing:border-box;text-decoration:none;color:#0E1A2B;border-bottom:1px solid #EDEFF3">'
         '<div style="display:flex;flex:none"><div style="width:38px;height:38px;border-radius:19px;background:#E8ECF3;border:2px solid #FFFFFF;display:flex;align-items:center;justify-content:center;' + SER + ';font-size:15px;font-weight:600">{{ r.iniA }}</div>'
         '<div style="width:38px;height:38px;border-radius:19px;background:#F3E9D4;border:2px solid #FFFFFF;margin-left:-12px;display:flex;align-items:center;justify-content:center;' + SER + ';font-size:15px;font-weight:600">{{ r.iniB }}</div></div>'
         '<div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:600">{{ r.nameA }}</div><div style="font-size:12px;color:#4A5568;margin-top:2px">{{ r.nameB }} · {{ r.why }}</div></div>'
         '<span style="flex:none;font-size:11px;font-weight:700;border-radius:10px;padding:3px 9px;background:{{ r.bg }};color:{{ r.fg }}">{{ r.conf }}</span></a>')
body += '</sc-for></div>'
body += ENDSC + bar('<a href="Merge.dc.html" style="flex:1;height:52px;border-radius:14px;background:#0E1A2B;color:#FFFFFF;font-size:16px;font-weight:600;text-decoration:none;display:flex;align-items:center;justify-content:center">Merge all 3 exact matches</a>')
w('Duplicates.dc.html', 'Duplicates', body, script("""    const f = this.gs('filter', 'all');
    const all = [
      { a: 'Priya Nambiar', b: 'Priya Nambiar', why: 'same mobile', exact: true, conf: '100%' },
      { a: 'Marcus Oyelaran', b: 'M. Oyelaran', why: 'same email', exact: true, conf: '100%' },
      { a: 'Elena Voss', b: 'Elena Voss', why: 'same mobile', exact: true, conf: '100%' },
      { a: 'Tomás Aguirre', b: 'Tomas Aguirre', why: 'same company', exact: false, conf: '93%' },
      { a: 'Dmitri Kowalczyk', b: 'Dimitri Kowalczyk', why: 'similar name', exact: false, conf: '88%' },
      { a: 'Wen Zhao', b: 'Wen Zhao-Li', why: 'similar name', exact: false, conf: '84%' },
      { a: 'Hannah Whitcomb', b: 'Hannah Whitcombe', why: 'similar name', exact: false, conf: '81%' }
    ];
    const ini = (n) => n.split(' ').map((p) => p[0]).slice(0, 2).join('');
    const rows = all.filter((d) => f === 'all' || (f === 'exact' && d.exact) || (f === 'similar' && !d.exact)).map((d) => ({
      iniA: ini(d.a), iniB: ini(d.b), nameA: d.a, nameB: d.b, why: d.why, conf: d.conf,
      bg: d.exact ? '#0E1A2B' : '#FBF1DC', fg: d.exact ? '#FFFFFF' : '#7A4E0B'
    }));
    return Object.assign({ rows }, this.sv(['all', 'exact', 'similar'], f, 'filter'));"""))

# =====================================================================
# MERGE
# =====================================================================
body = header('Merge contacts', back='Duplicates.dc.html', sub='Pick the value to keep for each field') + SC
body += card('<div style="display:flex;align-items:center;gap:12px">' + avatar('PN', 48, '#0E1A2B', '#FFFFFF') + '<div style="flex:1"><div style="' + SER + ';font-size:20px;font-weight:600">Priya Nambiar</div>'
             '<div style="font-size:13px;color:#4A5568">Same mobile · +1 330 555 0142</div></div>' + chip('100%', ('#0E1A2B', '#FFFFFF')) + '</div>', '14px 16px', 6)
body += '<div style="display:flex;gap:8px;margin:14px 4px 6px 4px"><div style="width:58px;flex:none"></div><div style="flex:1;font-size:12px;font-weight:700;letter-spacing:0.06em;color:#7A5B22">A · SCANNED OCT 7</div><div style="flex:1;font-size:12px;font-weight:700;letter-spacing:0.06em;color:#7A5B22">B · SCANNED OCT 18</div></div>'
body += '<sc-for list="{{ rows }}" as="r" hint-placeholder-count="4">'
body += ('<div style="display:flex;gap:8px;align-items:stretch;margin-bottom:8px"><div style="width:58px;flex:none;font-size:12px;color:#4A5568;padding-top:14px">{{ r.label }}</div>'
         '<button onClick="{{ r.pickA }}" aria-pressed="{{ r.aOn }}" style="flex:1;min-width:0;min-height:56px;text-align:left;padding:8px 10px;border-radius:12px;font-size:13px;font-weight:600;word-break:break-all;cursor:pointer;color:#0E1A2B;background:{{ r.aBg }};border:1.5px solid {{ r.aBd }}">{{ r.a }}</button>'
         '<button onClick="{{ r.pickB }}" aria-pressed="{{ r.bOn }}" style="flex:1;min-width:0;min-height:56px;text-align:left;padding:8px 10px;border-radius:12px;font-size:13px;font-weight:600;word-break:break-all;cursor:pointer;color:#0E1A2B;background:{{ r.bBg }};border:1.5px solid {{ r.bBd }}">{{ r.b }}</button></div>')
body += '</sc-for>'
body += '<div style="margin:8px 4px 0 4px;font-size:12px;color:#4A5568;line-height:1.5">Values you do not pick stay on the merged contact as alternates. Both card images are kept. Notes and tags are combined.</div>'
body += ENDSC + bar(boutline('Not a duplicate', 'Duplicates.dc.html') + bprimary('Merge 2 into 1', 'Duplicates.dc.html'))
w('Merge.dc.html', 'Merge contacts', body, script("""    const p = this.gs('picks', { title: 'a', company: 'a', office: 'a', email: 'b' });
    const defs = [
      { k: 'title', label: 'Title', a: 'Director of Procurement', b: 'Procurement Director' },
      { k: 'company', label: 'Company', a: 'Halden Tooling Group', b: 'Halden Tooling' },
      { k: 'office', label: 'Office', a: '+1 330 555 0188', b: 'Not on card' },
      { k: 'email', label: 'Email', a: 'p.nambiar@haldentooling.example', b: 'priya.n@haldentooling.example' }
    ];
    const rows = defs.map((d) => {
      const a = p[d.k] === 'a';
      return {
        label: d.label, a: d.a, b: d.b, aOn: a, bOn: !a,
        aBg: a ? '#E8ECF3' : '#FFFFFF', aBd: a ? '#0E1A2B' : '#D5DAE1', bBg: a ? '#FFFFFF' : '#E8ECF3', bBd: a ? '#D5DAE1' : '#0E1A2B',
        pickA: () => this.setState({ picks: Object.assign({}, p, { [d.k]: 'a' }) }),
        pickB: () => this.setState({ picks: Object.assign({}, p, { [d.k]: 'b' }) })
      };
    });
    return { rows };"""))

# =====================================================================
# FOLLOW-UPS
# =====================================================================
body = header('Follow-ups', sub='6 open · today is Mon, Oct 19') + SC
body += ('<div style="display:flex;gap:10px;margin-top:6px">'
         '<div style="flex:1;padding:12px;border-radius:16px;background:#FBF1DC"><div style="' + SER + ';font-size:26px;font-weight:600;color:#7A4E0B;line-height:1">1</div><div style="font-size:12px;color:#7A4E0B;margin-top:4px">Overdue</div></div>'
         '<div style="flex:1;padding:12px;border-radius:16px;background:#E8ECF3"><div style="' + SER + ';font-size:26px;font-weight:600;line-height:1">3</div><div style="font-size:12px;color:#4A5568;margin-top:4px">This week</div></div>'
         '<div style="flex:1;padding:12px;border-radius:16px;background:#FFFFFF;border:1px solid #E2E5EA"><div style="' + SER + ';font-size:26px;font-weight:600;line-height:1">2</div><div style="font-size:12px;color:#4A5568;margin-top:4px">Later</div></div></div>')
body += '<sc-for list="{{ groups }}" as="g" hint-placeholder-count="3">'
body += '<div style="margin:18px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">{{ g.title }}</div>'
body += '<div style="border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden"><sc-for list="{{ g.items }}" as="it" hint-placeholder-count="2">'
body += ('<div style="display:flex;align-items:center;gap:6px;min-height:72px;padding:6px 6px 6px 4px;border-bottom:1px solid #EDEFF3">'
         '<button onClick="{{ it.toggle }}" aria-pressed="{{ it.done }}" aria-label="Mark done" style="width:44px;height:44px;border:0;background:transparent;cursor:pointer;display:flex;align-items:center;justify-content:center;flex:none">'
         '<span style="width:24px;height:24px;border-radius:12px;box-sizing:border-box;border:2px solid #0E1A2B;background:{{ it.dotBg }};display:flex;align-items:center;justify-content:center;color:#FFFFFF">' + svg(CHECK, 14, '3') + '</span></button>'
         '<div style="flex:1;min-width:0;opacity:{{ it.opacity }}"><div style="font-size:15px;font-weight:600">{{ it.name }}</div><div style="font-size:13px;color:#4A5568;margin-top:2px">{{ it.task }}</div>'
         '<span style="display:inline-block;margin-top:5px;font-size:11px;font-weight:700;border-radius:10px;padding:2px 9px;background:{{ it.bg }};color:{{ it.fg }}">{{ it.due }}</span></div>'
         '<a href="{{ it.mail }}" aria-label="Email" style="width:44px;height:44px;border-radius:22px;background:#E8ECF3;color:#0E1A2B;display:flex;align-items:center;justify-content:center;text-decoration:none;flex:none">' + svg(MAIL, 19) + '</a></div>')
body += '</sc-for></div></sc-for>'
body += ENDSC
w('Followups.dc.html', 'Follow-ups', body, script("""    const done = this.gs('done', {});
    const mk = (id, name, task, due, kind, mail) => ({
      name, task, due, mail,
      done: !!done[id], dotBg: done[id] ? '#0E1A2B' : '#FFFFFF', opacity: done[id] ? '0.45' : '1',
      bg: kind === 'over' ? '#FBF1DC' : '#E8ECF3', fg: kind === 'over' ? '#7A4E0B' : '#0E1A2B',
      toggle: () => this.setState({ done: Object.assign({}, done, { [id]: !done[id] }) })
    });
    const groups = [
      { title: 'OVERDUE', items: [mk('dw', 'Dana Whitfield', 'Send revised quote', 'Oct 16 · 3 days overdue', 'over', 'mailto:d.whitfield@example.com')] },
      { title: 'THIS WEEK', items: [
        mk('mo', 'Marcus Oyelaran', 'Congratulate on new role at Corvane', 'Oct 22', 'wk', 'mailto:m.oyelaran@corvane.example'),
        mk('ro', 'Renata Okafor', 'Introduce yourself, confirm contact info', 'Oct 23', 'wk', 'mailto:r.okafor@northgatefasteners.example'),
        mk('ta', 'Tomás Aguirre', 'Confirm hydraulic fittings spec', 'Oct 24', 'wk', 'mailto:t.aguirre@calderhydraulics.example')] },
      { title: 'LATER', items: [
        mk('pn', 'Priya Nambiar', 'Send die insert pricing', 'Oct 27', 'later', 'mailto:p.nambiar@haldentooling.example'),
        mk('dk', 'Dmitri Kowalczyk', 'Schedule plant visit', 'Oct 27', 'later', 'mailto:d.kowalczyk@haldentooling.example')] }
    ];
    return { groups };"""))

# =====================================================================
# TAGS
# =====================================================================
body = header('Tags', sub='Organize people your way', right=circle_btn('Tags.dc.html', PLUS, 'New tag')) + SC
body += '<div style="margin-top:6px;display:flex;align-items:center;gap:10px;height:48px;padding:0 14px;border-radius:14px;background:#FFFFFF;border:1px solid #D5DAE1;color:#4A5568">' + svg('M11 4a7 7 0 100 14 7 7 0 000-14zM20 20l-4-4', 18) + '<span style="font-size:15px">Search tags</span></div>'
body += '<div style="margin:18px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">LEAD RATING</div>'
body += ('<div style="display:flex;gap:10px"><a href="Main.dc.html" style="flex:1;padding:12px;border-radius:16px;background:#F8E1DD;color:#8C2F1F;text-decoration:none"><div style="' + SER + ';font-size:24px;font-weight:600;line-height:1">9</div><div style="font-size:12px;font-weight:600;margin-top:4px">Hot</div></a>'
         '<a href="Main.dc.html" style="flex:1;padding:12px;border-radius:16px;background:#FBF1DC;color:#7A4E0B;text-decoration:none"><div style="' + SER + ';font-size:24px;font-weight:600;line-height:1">38</div><div style="font-size:12px;font-weight:600;margin-top:4px">Warm</div></a>'
         '<a href="Main.dc.html" style="flex:1;padding:12px;border-radius:16px;background:#E1EAF5;color:#1F4A78;text-decoration:none"><div style="' + SER + ';font-size:24px;font-weight:600;line-height:1">71</div><div style="font-size:12px;font-weight:600;margin-top:4px">Cold</div></a></div>')
body += '<div style="margin:18px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">ALL TAGS</div>' + '<div style="border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden">'
for name, n, color in [('Procurement', 142, '#0E1A2B'), ('Vendor', 64, '#4A5568'), ('Decision maker', 47, '#B08A4A'), ('Expo 2026', 31, '#B08A4A'), ('Quote pending', 18, '#7A4E0B'), ('Former employee', 12, '#8793A5')]:
    body += ('<a href="Main.dc.html" style="display:flex;align-items:center;gap:12px;min-height:60px;padding:6px 16px;text-decoration:none;color:#0E1A2B;border-bottom:1px solid #EDEFF3">'
             '<span style="width:12px;height:12px;border-radius:6px;background:' + color + ';flex:none"></span><span style="flex:1;font-size:16px;font-weight:600">' + name + '</span>'
             '<span style="font-size:14px;color:#4A5568">' + str(n) + '</span><span style="color:#4A5568">' + svg(CHEV, 16, '2.4') + '</span></a>')
body += '</div><div style="margin:10px 4px 0 4px;font-size:12px;color:#4A5568;line-height:1.5">Long-press a tag to rename, recolor, or merge it into another tag.</div>'
body += ENDSC
w('Tags.dc.html', 'Tags', body)

# =====================================================================
# CONTACT EDIT
# =====================================================================
body = header('Edit contact', back='Detail.dc.html', sub='Priya Nambiar') + SC
f = inp('First name', 'Priya', 'f1') + inp('Last name', 'Nambiar', 'f2')
form = '<div style="display:flex;gap:10px">' + f + '</div>'
form += pair(inp('Title', 'Director of Procurement', 'f3'))
form += pair(inp('Company', 'Halden Tooling Group', 'f4'))
form += pair(inp('Mobile', '+1 330 555 0142', 'f5', 'tel'), inp('Office', '+1 330 555 0188', 'f6', 'tel'))
form += pair(inp('Email', 'p.nambiar@haldentooling.example', 'f7', 'email'))
form += pair(inp('Website', 'haldentooling.example', 'f8'), '<a href="https://haldentooling.example" target="_blank" rel="noopener" aria-label="Open website in browser" style="align-self:flex-end;width:48px;height:48px;border-radius:12px;border:1px solid #D5DAE1;display:flex;align-items:center;justify-content:center;color:#0E1A2B;text-decoration:none;flex:none">' + svg(GLOBE, 20) + '</a>')
form += pair(inp('Address', '4200 Industrial Pkwy, Akron, OH 44311', 'f9'))
body += card(form, '16px', 6)
body += card('<div style="font-size:12px;font-weight:600;color:#4A5568;margin-bottom:6px">Lead rating</div>' + seg([('hot', 'Hot', '1'), ('warm', 'Warm', '1'), ('cold', 'Cold', '1')])
             + pair(inp('Follow up', '2026-10-27', 'f10', 'date'), inp('Met at', 'Fabricators Expo 2026', 'f11')) + pair(inp('Tags', 'Procurement, Expo 2026', 'f12')), '16px', 12)
body += card('<label for="f13" style="display:block;font-size:12px;font-weight:600;color:#4A5568;margin-bottom:5px">Notes</label><textarea id="f13" rows="4" style="width:100%;box-sizing:border-box;border:1px solid #D5DAE1;border-radius:12px;padding:12px 14px;font-size:16px;line-height:1.4;background:#FFFFFF;color:#0E1A2B;resize:none">Quoted forging die inserts. Wants pricing by month end. Prefers email over calls.</textarea>', '16px', 12)
body += card(trow('Track career changes', 'Suggest an update when a new card shows a new company.', 'track', True), '4px 16px', 12)
body += ENDSC + bar(boutline('Cancel', 'Detail.dc.html') + bprimary('Save', 'Detail.dc.html'))
w('ContactEdit.dc.html', 'Edit contact', body, script("""    const o = this.sv(['hot', 'warm', 'cold'], this.gs('rating', 'warm'), 'rating');
    this.tg(o, 'track', this.gs('track', true));
    return o;"""))

# =====================================================================
# IMPORT
# =====================================================================
body = header('Import', sub='Bring contacts in, nothing leaves the phone') + SC
body += '<sc-for list="{{ srcs }}" as="s" hint-placeholder-count="3">'
body += ('<button onClick="{{ s.pick }}" aria-pressed="{{ s.on }}" style="display:flex;align-items:center;gap:12px;width:100%;text-align:left;margin-top:8px;padding:14px;border-radius:16px;background:{{ s.bg }};border:1.5px solid {{ s.bd }};cursor:pointer;color:#0E1A2B">'
         '<span style="width:22px;height:22px;border-radius:11px;box-sizing:border-box;border:2px solid {{ s.bd }};background:{{ s.dot }};flex:none"></span>'
         '<span style="flex:1"><span style="display:block;font-size:15px;font-weight:600">{{ s.title }}</span><span style="display:block;font-size:13px;color:#4A5568;margin-top:2px">{{ s.desc }}</span></span></button>')
body += '</sc-for>'
body += card(lab('PREVIEW') + '<div style="' + SER + ';font-size:26px;font-weight:600;line-height:1.1">{{ total }} contacts</div><div style="font-size:14px;color:#4A5568;margin-top:4px">{{ dups }} will be merged as duplicates · {{ review }} need review</div>', '16px', 12)
body += '<sc-if value="{{ isCsv }}" hint-placeholder-val="{{ false }}">' + card(lab('COLUMN MAPPING') + ''.join(
    '<div style="display:flex;align-items:center;gap:8px;min-height:40px;border-bottom:1px solid #EDEFF3;font-size:14px"><span style="flex:1;color:#4A5568">' + a + '</span><span style="color:#4A5568">' + svg('M5 12h14M13 6l6 6-6 6', 16, '2.2') + '</span><span style="flex:1;font-weight:600;text-align:right">' + b + '</span></div>'
    for a, b in [('First Name', 'First name'), ('Last Name', 'Last name'), ('Organization', 'Company'), ('Job Title', 'Title'), ('Mobile Phone', 'Mobile'), ('E-mail Address', 'Email')]), '16px', 12) + '</sc-if>'
body += '<div style="margin:12px 4px 0 4px;font-size:12px;color:#4A5568;line-height:1.5">Imported contacts get an Imported tag so you can review or undo the batch.</div>'
body += ENDSC + bar(bprimary('Import {{ total }} contacts', 'Main.dc.html', '1'))
w('Import.dc.html', 'Import', body, script("""    const k = this.gs('src', 'vcf');
    const defs = [
      { k: 'vcf', title: 'vCard file (.vcf)', desc: 'One or many contacts from another app or card reader.', total: 212, dups: 9, review: 3 },
      { k: 'csv', title: 'CSV spreadsheet', desc: 'Map columns from Excel, HubSpot, or Outlook exports.', total: 540, dups: 27, review: 14 },
      { k: 'phone', title: 'Phone contacts', desc: 'Read once with permission. Not kept in sync.', total: 318, dups: 41, review: 0 }
    ];
    const cur = defs.find((d) => d.k === k);
    const srcs = defs.map((d) => ({
      title: d.title, desc: d.desc, on: k === d.k,
      bg: k === d.k ? '#E8ECF3' : '#FFFFFF', bd: k === d.k ? '#0E1A2B' : '#D5DAE1', dot: k === d.k ? '#0E1A2B' : '#FFFFFF',
      pick: () => this.setState({ src: d.k })
    }));
    return { srcs, total: String(cur.total), dups: String(cur.dups), review: String(cur.review), isCsv: k === 'csv' };"""))

# =====================================================================
# EXPORT
# =====================================================================
body = header('Export and backup', sub='Your data, in formats you can use') + SC
body += card(lab('WHAT TO EXPORT') + seg([('all', 'Everyone', '1'), ('tag', 'Tag', '1'), ('event', 'Event', '1')])
             + '<div style="margin-top:12px;font-size:14px;color:#4A5568">{{ scopeLabel }}</div>', '16px', 6)
body += '<div style="margin:18px 4px 4px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">FORMAT</div>'
body += '<sc-for list="{{ fmts }}" as="s" hint-placeholder-count="5">'
body += ('<button onClick="{{ s.pick }}" aria-pressed="{{ s.on }}" style="display:flex;align-items:center;gap:12px;width:100%;text-align:left;margin-top:8px;padding:12px 14px;border-radius:16px;background:{{ s.bg }};border:1.5px solid {{ s.bd }};cursor:pointer;color:#0E1A2B">'
         '<span style="width:22px;height:22px;border-radius:11px;box-sizing:border-box;border:2px solid {{ s.bd }};background:{{ s.dot }};flex:none"></span>'
         '<span style="flex:1"><span style="display:block;font-size:15px;font-weight:600">{{ s.title }}</span><span style="display:block;font-size:12px;color:#4A5568;margin-top:2px">{{ s.desc }}</span></span></button>')
body += '</sc-for>'
body += card(trow('Include card images', 'Adds front and back photos.', 'imgs') + trow('Include notes and tags', '', 'notes', True), '4px 16px', 12)
body += ('<button style="width:100%;margin-top:12px;height:52px;border:0;border-radius:14px;background:#0E1A2B;color:#FFFFFF;font-size:16px;font-weight:600;cursor:pointer">{{ exportLabel }}</button>')
body += '<div style="margin:22px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">BACKUP</div>'
body += card('<div style="display:flex;align-items:center;gap:12px"><div style="flex:1"><div style="font-size:15px;font-weight:600">Last backup</div><div style="font-size:13px;color:#4A5568;margin-top:2px">Mon, Oct 12 · 412 MB with images</div></div></div>'
             '<div style="display:flex;gap:10px;margin-top:14px"><button style="flex:1.3;height:48px;border:0;border-radius:12px;background:#E8ECF3;color:#0E1A2B;font-size:14px;font-weight:600;cursor:pointer">Back up now (.zip)</button>'
             '<button style="flex:1;height:48px;border-radius:12px;border:1.5px solid #D5DAE1;background:#FFFFFF;color:#0E1A2B;font-size:14px;font-weight:600;cursor:pointer">Restore</button></div>', '16px', 0)
body += card(trow('Weekly auto-backup', 'Saves a .zip to a folder you choose.', 'auto', True), '4px 16px', 12)
body += ENDSC
w('Export.dc.html', 'Export and backup', body, script("""    const sc = this.gs('scope', 'all');
    const fm = this.gs('fmt', 'vcf3');
    const labels = { all: 'All 1,284 contacts', tag: 'Tag: Expo 2026 · 31 contacts', event: 'Event: Fabricators Expo 2026 · 31 contacts' };
    const counts = { all: '1,284', tag: '31', event: '31' };
    const defs = [
      { k: 'vcf3', title: 'vCard 3.0', desc: 'Default. Opens in every phone and desktop contacts app.' },
      { k: 'vcf4', title: 'vCard 4.0', desc: 'Newer standard. Some older apps reject it.' },
      { k: 'csvgen', title: 'CSV, generic', desc: 'Excel and Google Sheets.' },
      { k: 'csvhub', title: 'CSV, HubSpot columns', desc: 'Ready for HubSpot contact import.' },
      { k: 'csvsf', title: 'CSV, Salesforce columns', desc: 'Ready for Salesforce Data Import Wizard.' }
    ];
    const fmts = defs.map((d) => ({
      title: d.title, desc: d.desc, on: fm === d.k,
      bg: fm === d.k ? '#E8ECF3' : '#FFFFFF', bd: fm === d.k ? '#0E1A2B' : '#D5DAE1', dot: fm === d.k ? '#0E1A2B' : '#FFFFFF',
      pick: () => this.setState({ fmt: d.k })
    }));
    const o = Object.assign({ fmts, scopeLabel: labels[sc], exportLabel: 'Export ' + counts[sc] + ' contacts' }, this.sv(['all', 'tag', 'event'], sc, 'scope'));
    this.tg(o, 'imgs', this.gs('imgs', true));
    this.tg(o, 'notes', this.gs('notes', true));
    this.tg(o, 'auto', this.gs('auto', true));
    return o;"""))

# =====================================================================
# SYNC
# =====================================================================
body = header('Sync to desktop', sub='Same Wi-Fi. No account. No cloud.') + SC
body += '<div style="margin-top:6px">' + seg([('show', 'Show QR code', '1'), ('scan', 'Scan QR code', '1')]) + '</div>'
body += '<sc-if value="{{ isShow }}" hint-placeholder-val="{{ true }}">'
body += card('<div style="display:flex;flex-direction:column;align-items:center"><div style="padding:14px;border-radius:14px;background:#FFFFFF;border:1px solid #E2E5EA"><svg viewBox="0 0 25 25" width="196" height="196" shape-rendering="crispEdges" role="img" aria-label="Pairing QR code"><path d="{{ qrPath }}" fill="#0E1A2B"/></svg></div>'
             '<div style="margin-top:12px;font-size:15px;font-weight:600;text-align:center">Scan this with the desktop app</div>'
             '<div style="margin-top:4px;font-size:13px;color:#4A5568;text-align:center;line-height:1.45">This phone hosts. The code works once and expires in 2:00.</div>'
             '<div style="margin-top:10px;padding:6px 12px;border-radius:10px;background:#E8ECF3;font-size:12px;font-weight:600;font-family:ui-monospace,Menlo,monospace">192.168.1.42:48210</div></div>', '18px 16px', 12)
body += '<div style="margin:8px 4px 0 4px;font-size:12px;color:#4A5568;line-height:1.5">The sync server runs only while this screen is open. Traffic is encrypted and pinned to this phone\'s certificate.</div>'
body += '</sc-if>'
body += '<sc-if value="{{ isScan }}" hint-placeholder-val="{{ false }}">'
body += ('<div style="margin-top:12px;height:300px;border-radius:18px;background:#0E1A2B;position:relative;display:flex;align-items:center;justify-content:center;overflow:hidden">'
         '<div style="width:190px;height:190px;position:relative"><span style="position:absolute;left:0;top:0;width:36px;height:36px;border-left:4px solid #E3C48A;border-top:4px solid #E3C48A;border-radius:8px 0 0 0"></span>'
         '<span style="position:absolute;right:0;top:0;width:36px;height:36px;border-right:4px solid #E3C48A;border-top:4px solid #E3C48A;border-radius:0 8px 0 0"></span>'
         '<span style="position:absolute;left:0;bottom:0;width:36px;height:36px;border-left:4px solid #E3C48A;border-bottom:4px solid #E3C48A;border-radius:0 0 0 8px"></span>'
         '<span style="position:absolute;right:0;bottom:0;width:36px;height:36px;border-right:4px solid #E3C48A;border-bottom:4px solid #E3C48A;border-radius:0 0 8px 0"></span></div>'
         '<div style="position:absolute;left:0;right:0;bottom:16px;text-align:center;font-size:14px;color:#D3D9E3">Point at the QR code on the desktop</div></div>')
body += '<div style="margin:8px 4px 0 4px;font-size:12px;color:#4A5568;line-height:1.5">Use this when the desktop is the host, for example a work laptop that only allows outgoing connections.</div>'
body += '</sc-if>'
body += '<div style="margin:20px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">PAIRED DEVICES</div>'
body += '<div style="border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden">'
body += ('<div style="display:flex;align-items:center;gap:12px;min-height:76px;padding:10px 16px;border-bottom:1px solid #EDEFF3"><span style="width:38px;height:38px;border-radius:12px;background:#E8ECF3;display:flex;align-items:center;justify-content:center;flex:none">' + svg('M4 5h16v11H4zM9 20h6M12 16v4', 19) + '</span>'
         '<div style="flex:1"><div style="font-size:15px;font-weight:600">Home desktop</div><div style="font-size:12px;color:#4A5568;margin-top:2px">Windows · synced today 9:42 · 2 changes waiting</div></div>'
         '<button style="height:40px;padding:0 14px;border:0;border-radius:12px;background:#0E1A2B;color:#FFFFFF;font-size:13px;font-weight:600;cursor:pointer">Sync now</button></div>')
body += ('<div style="display:flex;align-items:center;gap:12px;min-height:76px;padding:10px 16px"><span style="width:38px;height:38px;border-radius:12px;background:#E8ECF3;display:flex;align-items:center;justify-content:center;flex:none">' + svg('M4 5h16v11H4zM9 20h6M12 16v4', 19) + '</span>'
         '<div style="flex:1"><div style="font-size:15px;font-weight:600">Office laptop</div><div style="font-size:12px;color:#4A5568;margin-top:2px">macOS · synced Oct 12 · up to date</div></div>'
         '<button style="height:40px;padding:0 14px;border-radius:12px;border:1.5px solid #D5DAE1;background:#FFFFFF;color:#0E1A2B;font-size:13px;font-weight:600;cursor:pointer">Forget</button></div>')
body += '</div>'
body += card(lab('CONFLICTS') + '<div style="font-size:14px;line-height:1.5">Newest edit wins. If both sides changed the same field, the contact goes to Review so you pick.</div><a href="Merge.dc.html" style="display:inline-block;margin-top:10px;font-size:14px;font-weight:600;color:#0E1A2B">Open conflict review</a>', '14px 16px', 12)
body += card(lab('NO SHARED WI-FI?') + '<div style="font-size:14px;line-height:1.5">Turn on the phone hotspot and join it from the desktop, or move a backup file instead.</div><a href="Export.dc.html" style="display:inline-block;margin-top:10px;font-size:14px;font-weight:600;color:#0E1A2B">Export a backup file</a>', '14px 16px', 12)
body += ENDSC
w('Sync.dc.html', 'Sync to desktop', body, script("""    const m = this.gs('mode', 'show');
    return Object.assign({ isShow: m === 'show', isScan: m === 'scan', qrPath: this.qr(4242) }, this.sv(['show', 'scan'], m, 'mode'));"""))

# =====================================================================
# MY CARD
# =====================================================================
body = header('My card', sub='Share your details in one tap', right=circle_btn('ContactEdit.dc.html', 'M4 20h4L19 9l-4-4L4 16z', 'Edit my card')) + SC
body += '<div style="margin-top:8px">' + minicard('YOUR COMPANY', 'Jordan Ellis', 'Process Engineer', 'M +1 330 555 0100<br>jordan.ellis@yourcompany.example<br>yourcompany.example') + '</div>'
body += card('<div style="display:flex;flex-direction:column;align-items:center"><div style="padding:14px;border-radius:14px;background:#FFFFFF;border:1px solid #E2E5EA"><svg viewBox="0 0 25 25" width="180" height="180" shape-rendering="crispEdges" role="img" aria-label="Your contact QR code"><path d="{{ qrPath }}" fill="#0E1A2B"/></svg></div>'
             '<div style="margin-top:10px;font-size:13px;color:#4A5568;text-align:center">Anyone can scan this with their camera to save your contact.</div></div>', '18px 16px', 14)
body += card(trow('Include mobile number', '', 'mob') + trow('Include office number', '', 'off') + trow('Include address', '', 'addr', True), '4px 16px', 12)
body += ENDSC + bar(boutline('Send by email', 'mailto:') + bprimary('Share vCard', 'MyCard.dc.html'))
w('MyCard.dc.html', 'My card', body, script("""    const o = { qrPath: this.qr(77) };
    this.tg(o, 'mob', this.gs('mob', true));
    this.tg(o, 'off', this.gs('off', true));
    this.tg(o, 'addr', this.gs('addr', false));
    return o;"""))

# =====================================================================
# SETTINGS
# =====================================================================
body = header('Settings') + SC
body += '<sc-for list="{{ groups }}" as="g" hint-placeholder-count="3">'
body += '<div style="margin:18px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">{{ g.title }}</div>'
body += '<div style="border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden"><sc-for list="{{ g.rows }}" as="r" hint-placeholder-count="3">'
body += ('<div style="display:flex;align-items:center;gap:12px;min-height:62px;padding:8px 16px;border-bottom:1px solid #EDEFF3"><div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:600">{{ r.label }}</div>'
         '<div style="font-size:12px;color:#4A5568;margin-top:2px">{{ r.sub }}</div></div>'
         '<sc-if value="{{ r.isToggle }}" hint-placeholder-val="{{ true }}"><button onClick="{{ r.toggle }}" aria-pressed="{{ r.on }}" aria-label="{{ r.label }}" style="width:52px;height:32px;border:0;border-radius:16px;cursor:pointer;position:relative;flex:none;background:{{ r.bg }}">'
         '<span style="position:absolute;top:3px;left:{{ r.left }};width:26px;height:26px;border-radius:13px;background:#FFFFFF;box-shadow:0 1px 3px rgba(0,0,0,0.3)"></span></button></sc-if>'
         '<sc-if value="{{ r.isValue }}" hint-placeholder-val="{{ false }}"><span style="display:flex;align-items:center;gap:4px;font-size:14px;color:#4A5568">{{ r.value }}<span>' + svg(CHEV, 16, '2.4') + '</span></span></sc-if></div>')
body += '</sc-for></div></sc-for>'
body += '<div style="margin:18px 4px 8px 4px;font-size:12px;font-weight:700;letter-spacing:0.08em;color:#7A5B22">ABOUT</div>'
body += ('<div style="border-radius:18px;background:#FFFFFF;border:1px solid #E2E5EA;overflow:hidden">'
         '<a href="https://example.com/privacy" target="_blank" rel="noopener" style="display:flex;align-items:center;gap:12px;min-height:62px;padding:8px 16px;text-decoration:none;color:#0E1A2B;border-bottom:1px solid #EDEFF3"><div style="flex:1"><div style="font-size:15px;font-weight:600">Privacy policy</div><div style="font-size:12px;color:#4A5568;margin-top:2px">Opens in your default browser</div></div>' + svg(GLOBE, 18) + '</a>'
         '<div style="display:flex;align-items:center;min-height:56px;padding:8px 16px"><div style="flex:1;font-size:15px;font-weight:600">Version</div><span style="font-size:14px;color:#4A5568">0.2.0</span></div></div>')
body += ENDSC
w('Settings.dc.html', 'Settings', body, script("""    const on = this.gs('on', {});
    const t = (id, label, sub, def) => {
      const v = on[id] === undefined ? def : on[id];
      return { label, sub, isToggle: true, isValue: false, value: '', on: v, bg: v ? '#0E1A2B' : '#8793A5', left: v ? '23px' : '3px',
        toggle: () => this.setState({ on: Object.assign({}, on, { [id]: !v }) }) };
    };
    const val = (label, sub, value) => ({ label, sub, isToggle: false, isValue: true, value, on: false, bg: '', left: '', toggle: () => {} });
    const groups = [
      { title: 'SCANNING', rows: [
        t('auto', 'Auto-capture', 'Take the photo when the card is steady.', true),
        t('keep', 'Keep original images', 'Needed to re-read a card later.', true),
        t('qr', 'Use QR codes on cards', 'Prefer a card\\'s vCard QR over OCR.', true),
        val('OCR languages', 'Latin script is always on.', 'English, Spanish'),
        val('Smart parsing (AI)', 'Off sends nothing off the device.', 'Off')] },
      { title: 'TAP CARDS (NFC)', rows: [
        t('nfc', 'Read tap cards', 'Scan > Tap. Uses the phone NFC reader.', true),
        t('nfcfetch', 'Fetch details from link cards', 'Off: link cards save the link only. On: reads the page over the internet.', false),
        t('nfcsave', 'Keep raw tag data', 'Stores the tag contents with the contact.', false)] },
      { title: 'CONTACTS', rows: [
        val('Default sort', '', 'Name'),
        val('vCard version', 'For sharing and export.', '3.0'),
        t('push', 'Add new contacts to phone', 'Writes to the phone contacts app.', false)] },
      { title: 'REMINDERS', rows: [
        t('notif', 'Follow-up notifications', '', true),
        val('Default follow-up delay', 'After a scan or event.', '3 days'),
        val('Daily digest', '', '8:00 AM')] },
      { title: 'CAREER TRACKING', rows: [
        t('career', 'Track job changes', 'Suggest updates when a new card shows a new company.', true),
        t('retire', 'Prompt for a replacement', 'When someone is marked retired or moved.', true),
        val('Search engine for web checks', 'Links open in your default browser.', 'Google')] },
      { title: 'SECURITY', rows: [
        t('lock', 'App lock', 'Fingerprint, face, or device passcode.', false),
        t('enc', 'Encrypt database', '', true),
        val('Auto-lock after', '', '1 minute')] }
    ];
    return { groups };"""))

# =====================================================================
# ONBOARDING
# =====================================================================
body = '<div style="flex:1;min-height:0;overflow-y:auto;padding:56px 20px 20px 20px">'
body += ('<div style="width:64px;height:64px;border-radius:18px;background:#0E1A2B;border:1.5px solid #B08A4A;display:flex;align-items:center;justify-content:center;color:#E3C48A">' + svg('M3 7a2 2 0 012-2h14a2 2 0 012 2v10a2 2 0 01-2 2H5a2 2 0 01-2-2zM7 11h7M7 14h4', 30) + '</div>'
         '<h1 style="margin:22px 0 0 0;' + SER + ';font-size:36px;font-weight:600;line-height:1.1;letter-spacing:-0.01em">Welcome to Card Organizer</h1>'
         '<div style="margin-top:10px;font-size:16px;line-height:1.5;color:#4A5568">Scan business cards, keep your network organized, and never lose a follow-up.</div>')
rows = ''
for id_, title, desc, d in [('cam', 'Camera', 'To scan cards. Text is read on this device.', 'M4 8h3l1.500-2h7L17 8h3v11H4zM12 10a3.500 3.500 0 100 7 3.500 3.500 0 000-7z'),
                            ('notif', 'Notifications', 'For follow-up reminders you set.', 'M6 16V11a6 6 0 0112 0v5l2 2H4zM10 21h4'),
                            ('cont', 'Contacts (optional)', 'To import or add contacts to your phone.', 'M12 12a4 4 0 100-8 4 4 0 000 8zM4 20c0-4 3.500-6 8-6s8 2 8 6')]:
    I = id_[0].upper() + id_[1:]
    rows += ('<div style="display:flex;align-items:center;gap:12px;min-height:76px;padding:8px 0;border-bottom:1px solid #EDEFF3"><span style="width:42px;height:42px;border-radius:12px;background:#E8ECF3;display:flex;align-items:center;justify-content:center;flex:none">' + svg(d, 20) + '</span>'
             '<div style="flex:1"><div style="font-size:15px;font-weight:600">' + title + '</div><div style="font-size:12px;color:#4A5568;margin-top:2px">' + desc + '</div></div>'
             '<button onClick="{{ toggle' + I + ' }}" aria-pressed="{{ ' + id_ + 'On }}" style="height:40px;min-width:80px;padding:0 14px;border:0;border-radius:12px;font-size:13px;font-weight:600;cursor:pointer;background:{{ ' + id_ + 'Bg }};color:{{ ' + id_ + 'Fg }}">{{ ' + id_ + 'Label }}</button></div>')
body += card(rows, '4px 16px', 24)
body += ('<div style="display:flex;align-items:flex-start;gap:10px;margin-top:16px;padding:0 4px;font-size:13px;color:#4A5568;line-height:1.5"><span style="color:#0E1A2B;flex:none">' + svg(LOCK, 18) + '</span><span>Everything stays on your device. No account, no cloud. Sync is a QR code between your own devices.</span></div>')
body += '</div>' + bar(boutline('Skip', 'Main.dc.html', '1') + bprimary('Get started', 'Main.dc.html', '1.6'))
w('Onboarding.dc.html', 'Welcome', body, script("""    const o = {};
    ['cam', 'notif', 'cont'].forEach((id) => {
      const on = this.gs(id, false);
      const I = id[0].toUpperCase() + id.slice(1);
      o[id + 'On'] = on; o[id + 'Label'] = on ? 'Allowed' : 'Allow';
      o[id + 'Bg'] = on ? '#E8ECF3' : '#0E1A2B'; o[id + 'Fg'] = on ? '#0E1A2B' : '#FFFFFF';
      o['toggle' + I] = () => this.setState({ [id]: !on });
    });
    return o;"""))

# =====================================================================
# STATES
# =====================================================================
def state_panel(icon, ic_bg, ic_fg, title, desc, b1, b2):
    return card('<div style="display:flex;gap:14px"><span style="width:44px;height:44px;border-radius:14px;background:' + ic_bg + ';color:' + ic_fg + ';display:flex;align-items:center;justify-content:center;flex:none">' + svg(icon, 22) + '</span>'
                '<div style="flex:1"><div style="font-size:16px;font-weight:600">' + title + '</div><div style="font-size:14px;color:#4A5568;margin-top:4px;line-height:1.45">' + desc + '</div></div></div>'
                '<div style="display:flex;gap:10px;margin-top:14px">' + b1 + b2 + '</div>', '16px', 12)


def sbtn(label, href, primary):
    st = 'background:#0E1A2B;color:#FFFFFF;' if primary else 'border:1.5px solid #D5DAE1;background:#FFFFFF;color:#0E1A2B;'
    return '<a href="' + href + '" style="flex:1;height:46px;border-radius:12px;' + st + 'font-size:14px;font-weight:600;text-decoration:none;display:flex;align-items:center;justify-content:center">' + label + '</a>'


body = header('Empty and error states', sub='What the app shows when things go wrong') + SC
body += state_panel('M12 4l9 16H3zM12 10v4M12 17v.1', '#FBF1DC', '#7A4E0B', 'Could not read this card', 'The text was too small or blurred. Retake with more light, or type it in.', sbtn('Retake', 'Scan.dc.html', True), sbtn('Enter by hand', 'ContactEdit.dc.html', False))
body += state_panel('M3 7a2 2 0 012-2h14a2 2 0 012 2v10a2 2 0 01-2 2H5a2 2 0 01-2-2zM7 11h7M7 14h4', '#E8ECF3', '#0E1A2B', 'No contacts yet', 'Scan your first card, or import a vCard or CSV file.', sbtn('Scan a card', 'Scan.dc.html', True), sbtn('Import', 'Import.dc.html', False))
body += state_panel('M4 5h16v11H4zM9 20h6M12 16v4M3 3l18 18', '#FBF1DC', '#7A4E0B', 'Desktop not found', 'Both devices must be on the same Wi-Fi. Guest networks often block this. A phone hotspot works.', sbtn('Try again', 'Sync.dc.html', True), sbtn('Use a file', 'Export.dc.html', False))
body += state_panel('M12 3a9 9 0 100 18 9 9 0 000-18zM12 8v5M12 16v.1', '#E8ECF3', '#0E1A2B', 'No matches found', 'Nothing matches that search. Check the spelling, or search by company or tag.', sbtn('Clear search', 'Main.dc.html', True), '')
body += ENDSC
w('States.dc.html', 'States', body)

# =====================================================================
# MENU (rewritten, scrollable)
# =====================================================================
def nav(label, href, d, active=False, badge=None):
    b = ''
    if badge:
        b = '<span style="min-width:26px;height:26px;padding:0 8px;box-sizing:border-box;border-radius:13px;background:' + badge[1] + ';color:' + badge[2] + ';font-size:13px;font-weight:700;display:flex;align-items:center;justify-content:center">' + badge[0] + '</span>'
    return ('<a href="' + href + '" style="display:flex;align-items:center;gap:14px;height:46px;padding:0 14px;border-radius:12px;text-decoration:none;font-size:16px;font-weight:' + ('700' if active else '500') + ';' + ('background:#E8ECF3;' if active else '') + 'flex:none">'
            + svg(d, 22) + '<span style="flex:1">' + label + '</span>' + b + '</a>')


items = [
    nav('Contacts', 'Main.dc.html', 'M12 12a4 4 0 100-8 4 4 0 000 8zM4 20c0-4 3.500-6 8-6s8 2 8 6', True),
    nav('Events', 'Events.dc.html', 'M3 7a2 2 0 012-2h14a2 2 0 012 2v13a2 2 0 01-2 2H5a2 2 0 01-2-2zM3 10h18M8 3v4M16 3v4', badge=('2', '#F3E9D4', '#6B4E17')),
    nav('Career moves', 'Career.dc.html', 'M7 7h11M14 3l4 4-4 4M17 17H6M10 13l-4 4 4 4', badge=('3', '#FBF1DC', '#7A4E0B')),
    nav('Scan cards', 'Scan.dc.html', 'M4 8h3l1.500-2h7L17 8h3v11H4zM12 10a3.500 3.500 0 100 7 3.500 3.500 0 000-7z'),
    nav('Review queue', 'Queue.dc.html', 'M5 6h14M5 12h14M5 18h9', badge=('12', '#0E1A2B', '#FFFFFF')),
    nav('Follow-ups', 'Followups.dc.html', 'M12 3a9 9 0 100 18 9 9 0 000-18zM12 7v5l3 2', badge=('4', '#FBF1DC', '#7A4E0B')),
    nav('Duplicates', 'Duplicates.dc.html', 'M5 4h9a1 1 0 011 1v9a1 1 0 01-1 1H5a1 1 0 01-1-1V5a1 1 0 011-1zM10 9h9a1 1 0 011 1v9a1 1 0 01-1 1h-9a1 1 0 01-1-1v-9a1 1 0 011-1z', badge=('7', '#E8ECF3', '#0E1A2B')),
    nav('Tags', 'Tags.dc.html', 'M3 12V4h8l10 10-8 8zM7.500 7.300v.1'),
    nav('Import', 'Import.dc.html', 'M21 12H9M13 8l-4 4 4 4M4 4v16'),
    nav('Export and backup', 'Export.dc.html', 'M12 4v11M8 11l4 4 4-4M5 19h14'),
    nav('Sync to desktop', 'Sync.dc.html', 'M4 12a8 8 0 0114-5.300L20 9M20 4v5h-5M20 12a8 8 0 01-14 5.300L4 15M4 20v-5h5'),
]
foot = [
    nav('My card', 'MyCard.dc.html', 'M3 7a2 2 0 012-2h14a2 2 0 012 2v10a2 2 0 01-2 2H5a2 2 0 01-2-2zM7 10h4M7 14h3M15 10h2v4h-2z'),
    nav('Settings', 'Settings.dc.html', 'M12 9a3 3 0 100 6 3 3 0 000-6zM12 3v3M12 18v3M3 12h3M18 12h3M5.600 5.600l2.100 2.100M16.300 16.300l2.100 2.100M5.600 18.400l2.100-2.100M16.300 7.700l2.100-2.100'),
]
body = '''<div aria-hidden="true" style="position: absolute; left: 0; top: 0; right: 0; bottom: 0; padding: 14px 16px">
<div style="height: 44px"></div>
<div style="margin: 8px 4px 0 4px; font-family: 'Newsreader', Georgia, serif; font-size: 34px; font-weight: 600">Contacts</div>
<div style="margin-top: 150px; height: 400px; border-radius: 16px; background: #FFFFFF; border: 1px solid #E2E5EA"></div>
</div>
<a href="Main.dc.html" aria-label="Close menu" style="position: absolute; left: 0; top: 0; right: 0; bottom: 0; background: rgba(14,26,43,0.5)"></a>
<nav aria-label="Main menu" style="position: absolute; left: 0; top: 0; bottom: 0; width: 308px; background: #FFFFFF; display: flex; flex-direction: column; box-shadow: 8px 0 28px rgba(14,26,43,0.22)">
<div style="flex: none; background: #0E1A2B; color: #FFFFFF; padding: 36px 22px 20px 22px">
<div style="display: flex; align-items: center; gap: 12px">
<div style="width: 44px; height: 44px; border-radius: 12px; background: #1B2A41; border: 1.5px solid #B08A4A; display: flex; align-items: center; justify-content: center; flex: none">
<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#E3C48A" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 11h6M7 14h4"/></svg>
</div>
<div>
<div style="font-family: 'Newsreader', Georgia, serif; font-size: 22px; font-weight: 600; line-height: 1.1">Card Organizer</div>
<div style="font-size: 13px; color: #C9D1DD; margin-top: 2px">Your professional network</div>
</div>
</div>
<div style="display: flex; gap: 22px; margin-top: 18px">
<div><div style="font-family: 'Newsreader', Georgia, serif; font-size: 24px; font-weight: 600">1,284</div><div style="font-size: 12px; color: #C9D1DD">People</div></div>
<div><div style="font-family: 'Newsreader', Georgia, serif; font-size: 24px; font-weight: 600">312</div><div style="font-size: 12px; color: #C9D1DD">Companies</div></div>
<div><div style="font-family: 'Newsreader', Georgia, serif; font-size: 24px; font-weight: 600">6</div><div style="font-size: 12px; color: #C9D1DD">Events</div></div>
</div>
</div>
<div style="flex: 1; min-height: 0; overflow-y: auto; padding: 10px 10px; display: flex; flex-direction: column; gap: 2px">''' + ''.join(items) + '''</div>
<div style="flex: none; padding: 6px 10px 18px 10px; border-top: 1px solid #E2E5EA; display: flex; flex-direction: column; gap: 2px">''' + ''.join(foot) + '''</div>
</nav>
'''
w('Menu.dc.html', 'Menu', body)
# =====================================================================
# TAP CARD (NFC)
# =====================================================================
WAVES = ('<svg width="120" height="120" viewBox="0 0 120 120" fill="none" stroke="#0E1A2B" stroke-width="3" stroke-linecap="round" aria-hidden="true">'
         '<rect x="38" y="12" width="44" height="78" rx="8"/><path d="M52 22h16"/><path d="M30 100c18-9 42-9 60 0" stroke="#B08A4A"/><path d="M20 111c24-13 56-13 80 0" stroke="#B08A4A"/></svg>')
body = header('Tap card', back='Scan.dc.html', sub='Hold the card to the back of your phone') + SC
body += '<div style="margin-top:8px;display:flex;align-items:center;gap:8px;font-size:13px;color:#4A5568">' + chip('EVENT', BRASS) + 'Saving to Fabricators Expo 2026</div>'
body += '<div style="margin-top:14px">' + seg([('wait', 'Waiting', '1'), ('vcard', 'vCard card', '1.2'), ('link', 'Link card', '1.1')]) + '</div>'
body += '<div style="margin:6px 4px 0 4px;font-size:11px;color:#4A5568">Preview states, design only</div>'
body += '<sc-if value="{{ isWait }}" hint-placeholder-val="{{ true }}">' + card('<div style="display:flex;flex-direction:column;align-items:center;padding:10px 0">' + WAVES +
        '<div style="margin-top:10px;font-size:17px;font-weight:600">Waiting for a card</div><div style="margin-top:4px;font-size:13px;color:#4A5568;text-align:center;line-height:1.45">Touch the card to the top back of the phone, near the camera. Keep it still for a second.</div></div>', '18px 16px', 12) + '</sc-if>'
rows = ''.join('<div style="display:flex;align-items:center;min-height:46px;border-bottom:1px solid #EDEFF3"><span style="width:84px;flex:none;font-size:13px;color:#4A5568">' + a + '</span><span style="font-size:15px;font-weight:600;word-break:break-all">' + b + '</span></div>'
               for a, b in [('Company', 'Delmar Castings'), ('Mobile', '+1 440 555 0119'), ('Email', 's.whitaker@delmarcastings.example'), ('Address', '77 Foundry Ln, Elyria, OH')])
body += '<sc-if value="{{ isVcard }}" hint-placeholder-val="{{ false }}">' + card('<div style="display:flex;align-items:center;gap:12px;margin-bottom:8px">' + avatar('SW', 48, '#0E1A2B', '#FFFFFF') +
        '<div style="flex:1"><div style="' + SER + ';font-size:22px;font-weight:600">Sam Whitaker</div><div style="font-size:13px;color:#4A5568">VP, Sales</div></div>' + chip('VCARD', NAVY) + '</div>' + rows, '16px', 12) + \
        '<div style="margin:8px 4px 0 4px;font-size:12px;color:#4A5568">Full contact read from the card. No internet needed.</div></sc-if>'
body += '<sc-if value="{{ isLink }}" hint-placeholder-val="{{ false }}">' + card('<div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">' + chip('LINK', AMB) + '<span style="font-size:15px;font-weight:600">This card holds a web link</span></div>'
        '<div style="padding:10px 12px;border-radius:10px;background:#E8ECF3;font-size:13px;font-weight:600;font-family:ui-monospace,Menlo,monospace;word-break:break-all">https://delmarcastings.example/sam</div>'
        '<div style="margin-top:10px;font-size:13px;color:#4A5568;line-height:1.45">No contact details are stored on the card itself. Open the page, or save the link now and add details later.</div>'
        '<div style="display:flex;gap:10px;margin-top:14px">' + ext('https://delmarcastings.example/sam', 'Open in browser', '1', 48) + '<a href="ContactEdit.dc.html" style="flex:1;height:48px;border-radius:14px;background:#0E1A2B;color:#FFFFFF;font-size:15px;font-weight:600;text-decoration:none;display:flex;align-items:center;justify-content:center">Save link only</a></div>', '16px', 12) + \
        '<div style="margin:8px 4px 0 4px;font-size:12px;color:#4A5568;line-height:1.45">Opens in your default browser. To read details from the page automatically, turn on "Fetch details from link cards" in Settings. That uses the internet.</div></sc-if>'
body += card(lab('WORKS WITH') + '<div style="font-size:13px;line-height:1.55;color:#0E1A2B">NFC tap cards (13.56 MHz, such as NTAG213, 215, 216). iPhone reads while this screen is open. Cards that use 125 kHz RFID cannot be read by phones. Use a USB reader with the desktop app.</div>', '14px 16px', 14)
body += ENDSC + bar('<button onClick="{{ pickWait }}" style="flex:1;height:52px;border-radius:14px;border:1.5px solid #0E1A2B;background:#FFFFFF;color:#0E1A2B;font-size:16px;font-weight:600;cursor:pointer">Tap another</button>' + bprimary('Review and save', 'Review.dc.html'))
w('TapCard.dc.html', 'Tap card', body, script("""    const s = this.gs('stage', 'vcard');
    return Object.assign({ isWait: s === 'wait', isVcard: s === 'vcard', isLink: s === 'link' }, this.sv(['wait', 'vcard', 'link'], s, 'stage'));"""))

print('ok')
