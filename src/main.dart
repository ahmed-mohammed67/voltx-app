import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const VoltXApp());

const cyan = Color(0xFF00EAFF);
const green = Color(0xFF00FF9D);
const red = Color(0xFFFF405C);
const panel = Color(0xFF0B1828);
const muted = Color(0xFF8AA9BA);

class VoltXApp extends StatelessWidget {
  const VoltXApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VOLT-X',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF050B16)),
        home: const Dashboard(),
      );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with SingleTickerProviderStateMixin {
  String ip = '', err = '';
  bool demo = false, muted = false, dismissed = false;
  String alert = '';
  double v = 0, limit = 8;
  bool fault = false, online = false, relay = false, buzzer = false;
  int fails = 0, tick = 0;
  final List<double> history = [];
  final List<String> log = [];
  Timer? timer;
  late final AnimationController pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    timer?.cancel();
    pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      ip = p.getString('ip') ?? '';
      demo = p.getBool('demo') ?? false;
      muted = p.getBool('muted') ?? false;
    });
    if (ip.isEmpty && !demo && mounted) _settings();
  }

  void _apply(double nv, bool nf, bool nr, bool nb, double lim) {
    if (nf && !fault) {
      if (!muted) HapticFeedback.heavyImpact();
      dismissed = false;
      alert = '${nv.toStringAsFixed(2)} V at ${DateTime.now().toString().substring(11, 19)}';
      log.insert(0, '${DateTime.now().toString().substring(11, 19)}   ${nv.toStringAsFixed(2)} V   OVER VOLTAGE');
    }
    if (nf && fault && !muted && DateTime.now().second % 3 == 0) HapticFeedback.vibrate();
    setState(() {
      v = nv;
      fault = nf;
      relay = nr;
      buzzer = nb;
      limit = lim;
      online = true;
      err = '';
      fails = 0;
      history.add(nv);
      if (history.length > 60) history.removeAt(0);
    });
  }

  Future<void> _poll() async {
    if (demo) {
      tick++;
      final nv = 7.2 + 1.4 * math.sin(tick / 6);
      final nf = fault ? nv > 7.8 : nv >= 8.0;
      _apply(nv, nf, nf, nf && tick % 2 == 0, 8.0);
      return;
    }
    if (ip.isEmpty) return;
    try {
      final r = await http.get(Uri.parse('http://$ip/data')).timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      _apply((d['voltage'] as num).toDouble(), d['fault'] == true, d['relay'] == true,
          d['buzzer'] == true, (d['limit'] as num).toDouble());
    } catch (e) {
      if (!mounted) return;
      fails++;
      if (fails >= 3) setState(() { online = false; err = 'No response from ESP32'; });
    }
  }

  void _settings() {
    final ipC = TextEditingController(text: ip);
    bool d = demo;
    bool m = muted;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('CONNECTION SETTINGS', style: TextStyle(color: cyan, letterSpacing: 2)),
            const SizedBox(height: 14),
            TextField(
              controller: ipC,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'ESP32 IP (e.g. 192.168.0.3)'),
            ),
            SwitchListTile(
              value: d,
              onChanged: (x) => setS(() => d = x),
              title: const Text('Demo mode (no ESP32 needed)'),
              activeColor: cyan,
            ),
            SwitchListTile(
              value: m,
              onChanged: (x) => setS(() => m = x),
              title: const Text('Mute vibration alerts'),
              activeColor: cyan,
            ),
            TextButton(
              onPressed: () => HapticFeedback.heavyImpact(),
              child: const Text('TEST VIBRATION'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.setString('ip', ipC.text.trim());
                await p.setBool('demo', d);
                await p.setBool('muted', m);
                setState(() {
                  ip = ipC.text.trim();
                  demo = d;
                  muted = m;
                  fails = 0;
                  history.clear();
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('SAVE'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withAlpha(90))),
          child: Row(children: [
            Icon(icon, color: c, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
            ),
          ]),
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF17415A))),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final c = fault ? red : cyan;
    final status = demo ? 'DEMO MODE' : ip.isEmpty ? 'Set ESP32 IP in settings' : online ? 'ESP32 ONLINE  ($ip)' : 'OFFLINE: $err';
    final ok = demo || online;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A1C36), Color(0xFF050B16)]),
        ),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            Row(children: [
              const Icon(Icons.shield, color: cyan, size: 30),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('VOLT-X', style: TextStyle(color: cyan, fontSize: 24, letterSpacing: 5, fontWeight: FontWeight.bold)),
                  Text('VOLTAGE PROTECTION SYSTEM', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 2)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.tune, color: cyan), onPressed: _settings),
            ]),
            const SizedBox(height: 14),
            if (fault && !dismissed)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                decoration: BoxDecoration(color: red, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(child: Text('ALERT: over voltage $alert', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => dismissed = true)),
                ]),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.circle, size: 11, color: ok ? green : red),
                const SizedBox(width: 8),
                Expanded(child: Text(status, style: TextStyle(color: ok ? green : red, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: pulse,
              builder: (context, child) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: c, width: fault ? 2.5 : 1),
                  boxShadow: [BoxShadow(color: c.withAlpha(fault ? (40 + pulse.value * 130).toInt() : 40), blurRadius: 30, spreadRadius: 1)],
                ),
                child: child,
              ),
              child: Column(children: [
                SizedBox(
                  height: 240,
                  child: Stack(alignment: Alignment.center, children: [
                    CustomPaint(size: const Size(240, 240), painter: GaugePainter(v / (limit * 1.25), 1 / 1.25, c)),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(v.toStringAsFixed(2), style: TextStyle(color: c, fontSize: 54, fontWeight: FontWeight.bold)),
                      const Text('VOLTS', style: TextStyle(color: muted, letterSpacing: 4)),
                    ]),
                  ]),
                ),
                Text(fault ? '⚠ OVER VOLTAGE DETECTED' : '✓ SYSTEM NORMAL',
                    style: TextStyle(color: fault ? red : green, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Trip limit: ${limit.toStringAsFixed(2)} V', style: const TextStyle(color: muted)),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              _tile(Icons.power, 'RELAY', relay ? 'TRIPPED' : 'NORMAL', relay ? red : green),
              _tile(Icons.volume_up, 'BUZZER', buzzer ? 'BEEPING' : 'SILENT', buzzer ? red : green),
            ]),
            Row(children: [
              _tile(Icons.lightbulb, 'GREEN LED', fault ? 'OFF' : 'ON', fault ? Colors.grey : green),
              _tile(Icons.lightbulb, 'RED LED', fault ? 'ON' : 'OFF', fault ? red : Colors.grey),
            ]),
            const SizedBox(height: 10),
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LIVE VOLTAGE (LAST 60 s)', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              SizedBox(height: 140, width: double.infinity, child: CustomPaint(painter: ChartPainter(history, limit))),
            ])),
            const SizedBox(height: 12),
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('FAULT LOG', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              if (log.isEmpty) const Text('No faults recorded', style: TextStyle(color: green)),
              for (final l in log.take(8))
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(l, style: const TextStyle(color: red, fontSize: 13))),
            ])),
            const SizedBox(height: 16),
            const Center(child: Text('VOLT-X // ESP32 POWER MONITORING UNIT', style: TextStyle(color: Color(0xFF527184), fontSize: 11))),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double frac, tick;
  final Color color;
  GaugePainter(this.frac, this.tick, this.color);
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 18);
    const start = 0.75 * math.pi, sweep = 1.5 * math.pi;
    Paint p(Color col, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = col;
    final f = frac.clamp(0.0, 1.0).toDouble();
    c.drawArc(rect, start, sweep, false, p(const Color(0xFF1B2C3C), 16));
    c.drawArc(rect, start, sweep * f, false, p(color.withAlpha(110), 26)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    c.drawArc(rect, start, sweep * f, false, p(color, 16));
    final a = start + sweep * tick;
    final dir = Offset(math.cos(a), math.sin(a));
    final r = rect.width / 2;
    c.drawLine(rect.center + dir * (r - 16), rect.center + dir * (r + 16), Paint()..color = Colors.white..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant GaugePainter o) => true;
}

class ChartPainter extends CustomPainter {
  final List<double> h;
  final double limit;
  ChartPainter(this.h, this.limit);
  @override
  void paint(Canvas c, Size s) {
    final top = math.max(limit * 1.25, h.isEmpty ? 0.0 : h.reduce(math.max));
    double y(double val) => s.height - (val / top) * s.height;
    c.drawLine(Offset(0, y(limit)), Offset(s.width, y(limit)), Paint()..color = red.withAlpha(160)..strokeWidth = 1.5);
    if (h.length < 2) return;
    final path = Path();
    for (var i = 0; i < h.length; i++) {
      final x = s.width * i / (h.length - 1);
      if (i == 0) {
        path.moveTo(x, y(h[i]));
      } else {
        path.lineTo(x, y(h[i]));
      }
    }
    final fill = Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cyan.withAlpha(90), cyan.withAlpha(0)])
              .createShader(Offset.zero & s));
    c.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = cyan);
  }

  @override
  bool shouldRepaint(covariant ChartPainter o) => true;
}
