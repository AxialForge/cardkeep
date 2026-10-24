import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'content/content_model.dart';

/// What each illustration shows, for TalkBack.
String artDescription(Art a) => switch (a) {
  Art.welcome => 'Three business cards fan out and turn into tidy contacts.',
  Art.privacy => 'A phone with a lock, and a crossed-out cloud: nothing is uploaded.',
  Art.keeps => 'Contacts, photos and tags kept inside the phone behind a lock.',
  Art.tour => 'A row of eight dots lighting up one by one towards a finish flag.',
  Art.scanOne => 'A card is outlined, a wipe shows it being read, then it turns green and says Done.',
  Art.sweep => 'A phone view moves across four cards; each one is outlined, read and turns green.',
  Art.queue => 'A list of scanned cards; one with an amber label is fixed and turns green.',
  Art.personPlace => 'A switch between Person and Place, showing a person card and a shop card.',
  Art.organise => 'Four panels cycle: tags, a calendar reminder, two cards merging, a company.',
  Art.importExport => 'A contacts file flows into the phone, and a backup zip flows out.',
  Art.backup => 'A backup zip is made weekly on the phone and copied to a safe place.',
  Art.nfc => 'A card is tapped on the back of a phone and waves show it being read.',
  Art.myCard => 'Your own card with a QR code that another phone scans.',
  Art.camera => 'A camera icon with a pulsing ring.',
  Art.bell => 'A bell icon with a pulsing ring.',
  Art.nfcPhone => 'A contactless icon with a pulsing ring.',
  Art.setup => 'A slider icon with a pulsing ring.',
  Art.demo => 'Sample contacts you can add and remove.',
  Art.help => 'A help icon with a pulsing ring.',
};

IconData? _iconFor(Art a) => switch (a) {
  Art.camera => Icons.photo_camera_outlined,
  Art.bell => Icons.notifications_none,
  Art.nfcPhone => Icons.contactless_outlined,
  Art.setup => Icons.tune,
  Art.demo => Icons.groups_outlined,
  Art.help => Icons.help_outline,
  _ => null,
};

const _green = Color(0xFF2F9E5B);

/// A small looping illustration drawn in Flutter (no image files). With
/// "remove animations" on, it shows the finished frame and stands still.
class LessonArt extends StatefulWidget {
  final Art art;
  final double height;
  const LessonArt(this.art, {super.key, this.height = 170});

  @override
  State<LessonArt> createState() => _LessonArtState();
}

class _LessonArtState extends State<LessonArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations": show the finished frame and stand still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0.92;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(widget.art);
    return Semantics(
      image: true,
      label: artDescription(widget.art),
      child: ExcludeSemantics(
        child: Container(
          height: widget.height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Tokens.headerTint,
            borderRadius: BorderRadius.circular(Tokens.radius),
            border: Border.all(color: Tokens.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) =>
                CustomPaint(painter: icon == null ? _ArtPainter(widget.art, _c.value) : _PulsePainter(icon, _c.value)),
          ),
        ),
      ),
    );
  }
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

void _text(
  Canvas c,
  String s,
  Offset at, {
  double size = 11,
  Color? color,
  FontWeight w = FontWeight.w600,
  bool center = true,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: size, color: color ?? Tokens.ink, fontWeight: w, fontFamily: 'HankenGrotesk'),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
}

/// A business card: rounded rectangle, a name line and detail lines.
void _card(Canvas c, Rect r, {double angle = 0, Color? fill, double alpha = 1, int lines = 3, bool circle = false}) {
  c.save();
  c.translate(r.center.dx, r.center.dy);
  c.rotate(angle);
  final box = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
  final rr = RRect.fromRectAndRadius(box, const Radius.circular(6));
  c.drawRRect(rr.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.12 * alpha));
  c.drawRRect(rr, Paint()..color = (fill ?? const Color(0xFFFAF8F2)).withValues(alpha: alpha));
  c.drawRRect(
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.18 * alpha),
  );
  final ink = Colors.black.withValues(alpha: 0.7 * alpha);
  final pad = r.width * 0.1;
  var y = box.top + r.height * 0.22;
  if (circle) c.drawCircle(Offset(box.left + pad + 7, y), 6, Paint()..color = ink.withValues(alpha: 0.35 * alpha));
  final x0 = box.left + pad + (circle ? 18 : 0);
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(x0, y - 2.5, r.width * 0.42, 5), const Radius.circular(2.5)),
    Paint()..color = ink,
  );
  for (var i = 0; i < lines; i++) {
    y += r.height * 0.2;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(box.left + pad, y - 1.5, r.width * (0.7 - i * 0.12), 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = ink.withValues(alpha: 0.28 * alpha),
    );
  }
  c.restore();
}

void _outline(Canvas c, Rect r, double angle, Color color, {double width = 2.5, double grow = 4}) {
  c.save();
  c.translate(r.center.dx, r.center.dy);
  c.rotate(angle);
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r.width + grow, height: r.height + grow),
      const Radius.circular(8),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color,
  );
  c.restore();
}

/// The accent wipe sweeping across a card while it is read.
void _wipe(Canvas c, Rect r, double angle, double p, Color color) {
  c.save();
  c.translate(r.center.dx, r.center.dy);
  c.rotate(angle);
  final box = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
  c.clipRRect(RRect.fromRectAndRadius(box, const Radius.circular(6)));
  final x = box.left + (box.width + 24) * p - 12;
  c.drawRect(
    Rect.fromLTWH(x - 14, box.top, 28, box.height),
    Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.65), color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(x - 14, box.top, 28, box.height)),
  );
  c.restore();
}

void _done(Canvas c, Rect r, double angle, double p, {bool label = true}) {
  if (p <= 0) return;
  c.save();
  c.translate(r.center.dx, r.center.dy);
  c.rotate(angle);
  final box = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
  final rr = RRect.fromRectAndRadius(box, const Radius.circular(6));
  c.drawRRect(rr, Paint()..color = _green.withValues(alpha: 0.30 * p));
  c.drawRRect(
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _green.withValues(alpha: p),
  );
  if (label) {
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 58, height: 20),
      const Radius.circular(10),
    );
    c.drawRRect(pill, Paint()..color = _green.withValues(alpha: p));
    final path = Path()
      ..moveTo(-20, 0)
      ..lineTo(-16, 4)
      ..lineTo(-9, -3);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: p),
    );
    c.restore();
    _text(
      c,
      'Done',
      r.center + const Offset(7, 0),
      size: 11,
      color: Colors.white.withValues(alpha: p),
      w: FontWeight.w700,
    );
    return;
  }
  c.restore();
}

void _pill(Canvas c, String s, Offset center, Color bg, Color fg, {double size = 10.5}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: fg, fontFamily: 'HankenGrotesk'),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final r = Rect.fromCenter(center: center, width: tp.width + 18, height: tp.height + 8);
  c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(99)), Paint()..color = bg);
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

Rect _viewRect(Size s, {double w = 0.62}) =>
    Rect.fromCenter(center: s.center(Offset.zero), width: s.width * w, height: s.height * 0.86);

class _ArtPainter extends CustomPainter {
  final Art art;
  final double t;
  _ArtPainter(this.art, this.t);

  Color get accent => Tokens.brass;

  @override
  void paint(Canvas c, Size s) {
    switch (art) {
      case Art.welcome:
        _welcome(c, s);
      case Art.privacy:
        _privacy(c, s);
      case Art.keeps:
        _keeps(c, s);
      case Art.tour:
        _tour(c, s);
      case Art.scanOne:
        _scanOne(c, s);
      case Art.sweep:
        _sweep(c, s);
      case Art.queue:
        _queue(c, s);
      case Art.personPlace:
        _personPlace(c, s);
      case Art.organise:
        _organise(c, s);
      case Art.importExport:
        _importExport(c, s);
      case Art.backup:
        _backup(c, s);
      case Art.nfc:
        _nfc(c, s);
      case Art.myCard:
        _myCard(c, s);
      default:
        break;
    }
  }

  void _welcome(Canvas c, Size s) {
    final rise = Curves.easeOut.transform(_seg(t, 0, 0.35));
    final cw = s.width * 0.34, ch = cw * 0.58;
    for (var i = 0; i < 3; i++) {
      final spread = (i - 1) * 0.28 * rise;
      final r = Rect.fromCenter(
        center: Offset(s.width * 0.5 + (i - 1) * 40 * rise, s.height * 0.5 - 6 * rise),
        width: cw,
        height: ch,
      );
      _card(c, r, angle: spread, lines: 2);
    }
    final chips = ['Scan', 'Organise', 'Follow up'];
    for (var i = 0; i < 3; i++) {
      final p = _seg(t, 0.4 + i * 0.14, 0.52 + i * 0.14);
      if (p > 0) {
        _pill(
          c,
          chips[i],
          Offset(s.width * (0.24 + i * 0.26), s.height * 0.84),
          accent.withValues(alpha: 0.18 * p),
          Tokens.ink.withValues(alpha: p),
        );
      }
    }
  }

  void _privacy(Canvas c, Size s) {
    final phone = Rect.fromCenter(center: Offset(s.width * 0.34, s.height * 0.5), width: 62, height: s.height * 0.8);
    c.drawRRect(RRect.fromRectAndRadius(phone, const Radius.circular(12)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(phone, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.ink,
    );
    // lock
    final lock = Rect.fromCenter(center: phone.center + const Offset(0, 8), width: 26, height: 20);
    final p = 0.7 + 0.3 * math.sin(t * 2 * math.pi);
    c.drawRRect(RRect.fromRectAndRadius(lock, const Radius.circular(4)), Paint()..color = _green.withValues(alpha: p));
    c.drawArc(
      Rect.fromCenter(center: lock.topCenter, width: 16, height: 18),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _green,
    );
    // crossed-out cloud
    final cx = s.width * 0.7, cy = s.height * 0.46;
    final cloud = Path()
      ..addOval(Rect.fromCenter(center: Offset(cx - 16, cy + 6), width: 30, height: 24))
      ..addOval(Rect.fromCenter(center: Offset(cx + 2, cy - 4), width: 36, height: 34))
      ..addOval(Rect.fromCenter(center: Offset(cx + 20, cy + 6), width: 30, height: 24));
    c.drawPath(cloud, Paint()..color = Tokens.ink2.withValues(alpha: 0.35));
    c.drawLine(
      Offset(cx - 34, cy - 24),
      Offset(cx + 36, cy + 26),
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Tokens.hotFg,
    );
    _text(c, 'Nothing uploaded', Offset(s.width * 0.7, s.height * 0.88), size: 11, color: Tokens.ink2);
  }

  void _keeps(Canvas c, Size s) {
    final box = Rect.fromCenter(center: s.center(Offset.zero), width: s.width * 0.56, height: s.height * 0.8);
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(14)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.ink,
    );
    final labels = ['Contacts', 'Card photos', 'Tags and notes'];
    final k = (t * 3).floor().clamp(0, 2);
    for (var i = 0; i < 3; i++) {
      final y = box.top + 22 + i * 30.0;
      final on = i == k;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(box.left + 14, y - 11, box.width - 28, 22), const Radius.circular(6)),
        Paint()..color = on ? accent.withValues(alpha: 0.22) : Tokens.selected,
      );
      _text(c, labels[i], Offset(box.left + 24, y - 6), size: 11, color: Tokens.ink, center: false);
    }
    _text(c, 'Only you', Offset(s.width * 0.88, s.height * 0.5), size: 11, color: _green, w: FontWeight.w700);
  }

  void _tour(Canvas c, Size s) {
    const n = 8;
    final lit = (t * (n + 1)).floor();
    final y = s.height * 0.5;
    for (var i = 0; i < n; i++) {
      final x = s.width * (0.1 + 0.8 * i / (n - 1));
      c.drawCircle(Offset(x, y), 9, Paint()..color = i < lit ? accent : Tokens.hairline);
      if (i < n - 1) {
        c.drawLine(
          Offset(x + 10, y),
          Offset(s.width * (0.1 + 0.8 * (i + 1) / (n - 1)) - 10, y),
          Paint()
            ..strokeWidth = 2
            ..color = Tokens.hairline,
        );
      }
    }
    _text(c, 'About five minutes', Offset(s.width * 0.5, s.height * 0.8), size: 12, color: Tokens.ink2);
  }

  void _scanOne(Canvas c, Size s) {
    final view = _viewRect(s, w: 0.7);
    c.drawRRect(RRect.fromRectAndRadius(view, const Radius.circular(12)), Paint()..color = const Color(0xFF1B1B1A));
    final slide = Curves.easeOut.transform(_seg(t, 0, 0.18));
    final r = Rect.fromCenter(
      center: view.center + Offset(0, 14 * (1 - slide)),
      width: view.width * 0.56,
      height: view.height * 0.5,
    );
    _card(c, r, angle: -0.08, alpha: slide);
    final found = _seg(t, 0.2, 0.34);
    if (found > 0 && t < 0.78) {
      _outline(c, r, -0.08, accent.withValues(alpha: found * (0.7 + 0.3 * math.sin(t * 40))));
    }
    final w = _seg(t, 0.36, 0.72);
    if (w > 0 && w < 1) _wipe(c, r, -0.08, w, accent);
    _done(c, r, -0.08, _seg(t, 0.74, 0.84));
    final label = t < 0.2
        ? 'Point at a card'
        : t < 0.36
        ? 'Found'
        : t < 0.74
        ? 'Reading...'
        : 'Done';
    _text(c, label, Offset(view.center.dx, view.bottom - 12), size: 11, color: Colors.white70);
  }

  void _sweep(Canvas c, Size s) {
    final view = _viewRect(s, w: 0.88);
    c.drawRRect(RRect.fromRectAndRadius(view, const Radius.circular(12)), Paint()..color = const Color(0xFF1B1B1A));
    final cw = view.width * 0.2, ch = cw * 0.6;
    final pos = [
      Offset(view.left + view.width * 0.18, view.top + view.height * 0.3),
      Offset(view.left + view.width * 0.5, view.top + view.height * 0.34),
      Offset(view.left + view.width * 0.8, view.top + view.height * 0.3),
      Offset(view.left + view.width * 0.34, view.top + view.height * 0.7),
    ];
    final ang = [-0.18, 0.1, -0.06, 0.2];
    var done = 0;
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromCenter(center: pos[i], width: cw, height: ch);
      _card(c, r, angle: ang[i], lines: 2);
      final a = 0.08 + i * 0.2;
      final f = _seg(t, a, a + 0.06);
      final w = _seg(t, a + 0.06, a + 0.16);
      final d = _seg(t, a + 0.16, a + 0.2);
      if (d >= 1) done++;
      if (f > 0 && d < 1) _outline(c, r, ang[i], accent.withValues(alpha: f));
      if (w > 0 && w < 1) _wipe(c, r, ang[i], w, accent);
      if (d > 0) _done(c, r, ang[i], d, label: false);
    }
    // the moving phone view
    final px = view.left + view.width * (0.12 + 0.76 * _seg(t, 0.04, 0.9));
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(px, view.center.dy), width: view.width * 0.3, height: view.height * 0.92),
        const Radius.circular(10),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white38,
    );
    _pill(c, '$done of 4 done', Offset(view.center.dx, view.bottom - 12), _green, Colors.white);
  }

  void _queue(Canvas c, Size s) {
    final rows = [
      ('Dana Reyes', 'Blurry', Tokens.amberBg, Tokens.amberFg),
      ('Sam Okafor', 'Low confidence', Tokens.amberBg, Tokens.amberFg),
      ('Lakeside Hardware', 'Place', Tokens.selected, Tokens.ink2),
    ];
    final fixed = _seg(t, 0.5, 0.7);
    for (var i = 0; i < 3; i++) {
      final r = Rect.fromLTWH(s.width * 0.1, s.height * (0.12 + i * 0.28), s.width * 0.8, s.height * 0.22);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = Tokens.surface);
      c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(10)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Tokens.hairline,
      );
      _card(c, Rect.fromLTWH(r.left + 8, r.top + 7, 40, r.height - 14), lines: 1);
      _text(c, rows[i].$1, Offset(r.left + 58, r.top + 10), size: 12, color: Tokens.ink, center: false);
      if (i == 1 && fixed > 0.5) {
        _pill(c, 'Saved', Offset(r.left + 98, r.bottom - 12), _green.withValues(alpha: 0.2), _green);
      } else {
        _pill(c, rows[i].$2, Offset(r.left + (i == 1 ? 120 : 94), r.bottom - 12), rows[i].$3, rows[i].$4);
      }
    }
    if (_seg(t, 0.3, 0.5) > 0 && fixed < 0.5) {
      final p = _seg(t, 0.3, 0.5);
      c.drawCircle(Offset(s.width * 0.78, s.height * 0.5), 9 * p, Paint()..color = accent.withValues(alpha: 0.5));
    }
  }

  void _personPlace(Canvas c, Size s) {
    final person = t < 0.5;
    final sw = Rect.fromCenter(center: Offset(s.width * 0.5, s.height * 0.16), width: 150, height: 24);
    c.drawRRect(RRect.fromRectAndRadius(sw, const Radius.circular(12)), Paint()..color = Tokens.selected);
    final half = Rect.fromLTWH(person ? sw.left : sw.center.dx, sw.top, sw.width / 2, sw.height);
    c.drawRRect(
      RRect.fromRectAndRadius(half.deflate(2), const Radius.circular(10)),
      Paint()..color = accent.withValues(alpha: 0.35),
    );
    _text(c, 'Person', Offset(sw.left + sw.width * 0.25, sw.center.dy), size: 11);
    _text(c, 'Place', Offset(sw.left + sw.width * 0.75, sw.center.dy), size: 11);
    final r = Rect.fromCenter(
      center: Offset(s.width * 0.5, s.height * 0.6),
      width: s.width * 0.5,
      height: s.height * 0.52,
    );
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Tokens.hairline,
    );
    if (person) {
      c.drawCircle(Offset(r.left + 30, r.top + 30), 16, Paint()..color = Tokens.selected);
      _text(c, 'Maya Chen', Offset(r.left + 56, r.top + 16), size: 12, center: false);
      _text(c, 'VP Sales', Offset(r.left + 56, r.top + 34), size: 11, color: Tokens.ink2, center: false);
      _text(c, 'Mobile  216 555 0101', Offset(r.left + 14, r.top + 66), size: 10.5, color: Tokens.ink2, center: false);
    } else {
      final b = Rect.fromLTWH(r.left + 14, r.top + 16, 32, 28);
      c.drawRect(b, Paint()..color = Tokens.selected);
      c.drawRect(Rect.fromLTWH(b.left - 3, b.top - 7, 38, 9), Paint()..color = accent);
      _text(c, 'Lakeside Hardware', Offset(r.left + 56, r.top + 16), size: 12, center: false);
      _text(c, 'Store', Offset(r.left + 56, r.top + 34), size: 11, color: Tokens.ink2, center: false);
      _text(c, 'Mon-Sat 8am-7pm', Offset(r.left + 14, r.top + 66), size: 10.5, color: Tokens.ink2, center: false);
    }
  }

  void _organise(Canvas c, Size s) {
    final names = ['Tags', 'Follow-ups', 'Duplicates', 'Companies'];
    final k = (t * 4).floor().clamp(0, 3);
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(
        s.width * (0.08 + (i % 2) * 0.43),
        s.height * (0.1 + (i ~/ 2) * 0.44),
        s.width * 0.41,
        s.height * 0.38,
      );
      final on = i == k;
      c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()..color = on ? accent.withValues(alpha: 0.2) : Tokens.surface,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 2 : 1
          ..color = on ? accent : Tokens.hairline,
      );
      _text(c, names[i], Offset(r.center.dx, r.bottom - 12), size: 11);
      final m = r.center.translate(0, -8);
      switch (i) {
        case 0:
          _pill(c, 'Customers', m.translate(-4, -7), const Color(0xFF2C5D8F), Colors.white, size: 9);
          _pill(c, 'Imported', m.translate(10, 8), const Color(0xFF4F6B6B), Colors.white, size: 9);
        case 1:
          c.drawCircle(
            m,
            14,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Tokens.ink,
          );
          c.drawLine(
            m,
            m + const Offset(0, -9),
            Paint()
              ..strokeWidth = 2
              ..color = Tokens.ink,
          );
          c.drawLine(
            m,
            m + const Offset(7, 3),
            Paint()
              ..strokeWidth = 2
              ..color = Tokens.ink,
          );
        case 2:
          final a = on ? (1 - t * 4 % 1) * 10 : 4.0;
          _card(c, Rect.fromCenter(center: m.translate(-a, 0), width: 36, height: 22), lines: 1);
          _card(c, Rect.fromCenter(center: m.translate(a, 3), width: 36, height: 22), lines: 1);
        default:
          c.drawRect(Rect.fromCenter(center: m, width: 28, height: 26), Paint()..color = Tokens.ink2);
          for (var w = 0; w < 6; w++) {
            c.drawRect(
              Rect.fromLTWH(m.dx - 10 + (w % 3) * 8, m.dy - 9 + (w ~/ 3) * 10, 4, 5),
              Paint()..color = Tokens.surface,
            );
          }
      }
    }
  }

  void _importExport(Canvas c, Size s) {
    final y = s.height * 0.5;
    final phone = Rect.fromCenter(center: Offset(s.width * 0.5, y), width: 60, height: s.height * 0.8);
    c.drawRRect(RRect.fromRectAndRadius(phone, const Radius.circular(12)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(phone, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.ink,
    );
    final rows = (_seg(t, 0.15, 0.5) * 4).floor();
    for (var i = 0; i < 4; i++) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(phone.left + 8, phone.top + 14 + i * 20, 44, 12),
          const Radius.circular(3),
        ),
        Paint()..color = i < rows ? accent.withValues(alpha: 0.5) : Tokens.selected,
      );
    }
    final file = Rect.fromCenter(center: Offset(s.width * 0.17, y), width: 40, height: 50);
    c.drawRRect(RRect.fromRectAndRadius(file, const Radius.circular(5)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(file, const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Tokens.ink2,
    );
    _text(c, '.vcf', file.center, size: 11);
    final zip = Rect.fromCenter(center: Offset(s.width * 0.83, y), width: 40, height: 50);
    final z = _seg(t, 0.55, 0.75);
    c.drawRRect(
      RRect.fromRectAndRadius(zip, const Radius.circular(5)),
      Paint()..color = Tokens.surface.withValues(alpha: 0.4 + 0.6 * z),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(zip, const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Tokens.ink2.withValues(alpha: 0.4 + 0.6 * z),
    );
    _text(c, '.zip', zip.center, size: 11, color: Tokens.ink.withValues(alpha: 0.4 + 0.6 * z));
    final dx1 = s.width * (0.24 + 0.14 * _seg(t, 0.0, 0.5));
    if (t < 0.55) c.drawCircle(Offset(dx1, y), 5, Paint()..color = accent);
    final dx2 = s.width * (0.62 + 0.14 * _seg(t, 0.55, 1));
    if (t > 0.55) c.drawCircle(Offset(dx2, y), 5, Paint()..color = accent);
    _text(c, 'Import', Offset(s.width * 0.3, y + 26), size: 10.5, color: Tokens.ink2);
    _text(c, 'Back up', Offset(s.width * 0.7, y + 26), size: 10.5, color: Tokens.ink2);
  }

  void _backup(Canvas c, Size s) {
    final phone = Rect.fromCenter(center: Offset(s.width * 0.3, s.height * 0.5), width: 58, height: s.height * 0.8);
    c.drawRRect(RRect.fromRectAndRadius(phone, const Radius.circular(12)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(phone, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.ink,
    );
    final clock = Offset(s.width * 0.3, s.height * 0.4);
    c.drawCircle(
      clock,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
    final ang = t * 2 * math.pi;
    c.drawLine(
      clock,
      clock + Offset(math.sin(ang) * 10, -math.cos(ang) * 10),
      Paint()
        ..strokeWidth = 2
        ..color = accent,
    );
    _text(c, 'weekly', Offset(s.width * 0.3, s.height * 0.62), size: 10.5, color: Tokens.ink2);
    final lift = Curves.easeInOut.transform(_seg(t, 0.4, 0.85));
    final zip = Rect.fromCenter(
      center: Offset(s.width * (0.3 + 0.4 * lift), s.height * (0.78 - 0.28 * lift)),
      width: 36,
      height: 44,
    );
    c.drawRRect(RRect.fromRectAndRadius(zip, const Radius.circular(5)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(zip, const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Tokens.ink2,
    );
    _text(c, '.zip', zip.center, size: 10.5);
    final box = Rect.fromCenter(center: Offset(s.width * 0.74, s.height * 0.62), width: 64, height: 40);
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)), Paint()..color = Tokens.selected);
    _text(c, 'Safe place', box.center, size: 10.5);
    _text(c, 'computer or drive', Offset(s.width * 0.74, s.height * 0.86), size: 10, color: Tokens.ink2);
  }

  void _nfc(Canvas c, Size s) {
    final phone = Rect.fromCenter(center: Offset(s.width * 0.36, s.height * 0.5), width: 62, height: s.height * 0.84);
    c.drawRRect(RRect.fromRectAndRadius(phone, const Radius.circular(12)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(phone, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.ink,
    );
    final approach = Curves.easeOut.transform(_seg(t, 0, 0.4));
    final cx = s.width * (0.86 - 0.26 * approach);
    final card = Rect.fromCenter(center: Offset(cx, s.height * 0.5), width: 70, height: 42);
    _card(c, card, angle: 0.0, lines: 2);
    if (t > 0.4 && t < 0.8) {
      final k = _seg(t, 0.4, 0.8);
      for (var i = 0; i < 3; i++) {
        final rr = 10 + 26 * ((k + i / 3) % 1);
        c.drawArc(
          Rect.fromCircle(center: Offset(phone.right - 6, s.height * 0.5), radius: rr),
          -0.7,
          1.4,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = accent.withValues(alpha: 1 - (rr - 10) / 26),
        );
      }
    }
    _done(c, card, 0, _seg(t, 0.82, 0.92), label: false);
    _text(
      c,
      t < 0.4
          ? 'Hold the card to the back'
          : t < 0.8
          ? 'Reading...'
          : 'Review and save',
      Offset(s.width * 0.5, s.height * 0.92),
      size: 11,
      color: Tokens.ink2,
    );
  }

  void _myCard(Canvas c, Size s) {
    final card = Rect.fromCenter(
      center: Offset(s.width * 0.34, s.height * 0.5),
      width: s.width * 0.4,
      height: s.height * 0.62,
    );
    c.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(12)), Paint()..color = Colors.white);
    c.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Tokens.hairline,
    );
    final qr = Rect.fromCenter(center: card.center, width: card.width * 0.7, height: card.width * 0.7);
    const n = 9;
    final cell = qr.width / n;
    final rnd = math.Random(7);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final corner = (x < 3 && y < 3) || (x > 5 && y < 3) || (x < 3 && y > 5);
        if (corner || rnd.nextBool()) {
          c.drawRect(
            Rect.fromLTWH(qr.left + x * cell, qr.top + y * cell, cell - 0.5, cell - 0.5),
            Paint()..color = Colors.black87,
          );
        }
      }
    }
    final phone = Rect.fromCenter(center: Offset(s.width * 0.74, s.height * 0.5), width: 54, height: s.height * 0.76);
    c.drawRRect(RRect.fromRectAndRadius(phone, const Radius.circular(12)), Paint()..color = Tokens.surface);
    c.drawRRect(
      RRect.fromRectAndRadius(phone, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.ink,
    );
    final b = Rect.fromCenter(center: phone.center, width: 30, height: 30);
    const len = 8.0;
    final bp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = accent;
    for (final (cx, cy, dx, dy) in [
      (b.left, b.top, 1.0, 1.0),
      (b.right, b.top, -1.0, 1.0),
      (b.left, b.bottom, 1.0, -1.0),
      (b.right, b.bottom, -1.0, -1.0),
    ]) {
      c.drawLine(Offset(cx, cy), Offset(cx + dx * len, cy), bp);
      c.drawLine(Offset(cx, cy), Offset(cx, cy + dy * len), bp);
    }
    final scan = b.top + b.height * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
    c.drawLine(
      Offset(b.left, scan),
      Offset(b.right, scan),
      Paint()
        ..strokeWidth = 2
        ..color = _green,
    );
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.t != t || old.art != art;
}

/// Big icon with soft pulsing rings, for the permission and set-up pages.
class _PulsePainter extends CustomPainter {
  final IconData icon;
  final double t;
  _PulsePainter(this.icon, this.t);

  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1;
      c.drawCircle(
        center,
        34 + 40 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Tokens.brass.withValues(alpha: 0.5 * (1 - k)),
      );
    }
    c.drawCircle(center, 34, Paint()..color = Tokens.surface);
    c.drawCircle(
      center,
      34,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Tokens.brass,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontSize: 34, fontFamily: icon.fontFamily, package: icon.fontPackage, color: Tokens.ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.icon != icon;
}
