import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_config.dart';
import 'social.dart';

const accents = <String, Color>{
  'Bleu': Color(0xFF3B82F6),
  'Rouge': Color(0xFFE5486B),
  'Ambre': Color(0xFFFFB44A),
  'Vert': Color(0xFF2DD4A0),
  'Violet': Color(0xFF8B5CF6),
};
Color kAccent = const Color(0xFF3B82F6);
const cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)));
const brand = LinearGradient(
    colors: [Color(0xFF1E3A8A), Color(0xFFBE185D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Boot());
}

// Démarre Firebase et affiche l'erreur à l'écran si ça échoue ou dépasse 15 s
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  late final Future<void> init = Firebase.initializeApp(options: firebaseOptions)
      .timeout(const Duration(seconds: 15))
      .then((_) {});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: init,
      builder: (c, s) {
        if (s.hasError) {
          return MaterialApp(
              home: Scaffold(
                  body: Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText('Erreur de démarrage :\n${s.error}',
                              textAlign: TextAlign.center)))));
        }
        if (s.connectionState != ConnectionState.done) {
          return const MaterialApp(home: Loading('Démarrage de Firebase… (v3.1)'));
        }
        return const AeroApp();
      },
    );
  }
}

class AeroApp extends StatefulWidget {
  const AeroApp({super.key});
  @override
  State<AeroApp> createState() => _AeroAppState();
}

class _AeroAppState extends State<AeroApp> {
  SharedPreferences? p;
  String? perr;
  final Map<String, String> cfg = {'pseudo': '', 'sb': '', 'accent': 'Bleu', 'mode': '2'};

  @override
  void initState() {
    super.initState();
    loadPrefs().then((x) {
      for (final k in cfg.keys.toList()) {
        cfg[k] = x.getString('cfg_$k') ?? cfg[k]!;
      }
      setState(() => p = x);
    });
  }

  // Si le stockage du téléphone ne répond pas en 5 s, on ouvre l'appli quand même
  // (données non conservées) au lieu de rester bloqué sur le chargement.
  Future<SharedPreferences> loadPrefs() async {
    try {
      return await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
    } catch (e) {
      perr = '$e';
      SharedPreferences.setMockInitialValues({});
      return SharedPreferences.getInstance();
    }
  }

  void setCfg(String k, String v) {
    p?.setString('cfg_$k', v);
    setState(() => cfg[k] = v);
  }

  ThemeData theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent, brightness: b),
        scaffoldBackgroundColor:
            b == Brightness.dark ? const Color(0xFF0B1220) : const Color(0xFFF3F5FA),
        inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
      );

  @override
  Widget build(BuildContext context) {
    kAccent = accents[cfg['accent']] ?? accents['Bleu']!;
    final mi = (int.tryParse(cfg['mode']!) ?? 2).clamp(0, 2).toInt();
    return MaterialApp(
      title: 'AeroSimAPP',
      debugShowCheckedModeBanner: false,
      themeMode: [ThemeMode.system, ThemeMode.light, ThemeMode.dark][mi],
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      builder: (c, child) => Column(children: [
        Expanded(child: child!),
        if (perr != null)
          Material(
              color: const Color(0xFFB91C1C),
              child: SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          'Stockage indisponible, données non conservées : $perr',
                          style: const TextStyle(color: Colors.white, fontSize: 12))))),
      ]),
      home: p == null
          ? const Loading('Chargement des réglages…')
          : AuthGate(
              onUsername: (u) {
                if (cfg['pseudo'] != u) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => setCfg('pseudo', u));
                }
              },
              child: Home(cfg: cfg, setCfg: setCfg, prefs: p!),
            ),
    );
  }
}

class Flight {
  final int id;
  final String dep, arr, date, avion, note;
  final int dur;
  Flight(this.id, this.dep, this.arr, this.date, this.dur, this.avion, this.note);
  Map<String, dynamic> toJson() => {
        'id': id, 'dep': dep, 'arr': arr, 'date': date,
        'dur': dur, 'avion': avion, 'note': note
      };
  factory Flight.fromJson(Map<String, dynamic> j) => Flight(j['id'], j['dep'],
      j['arr'], j['date'], j['dur'], j['avion'], j['note'] ?? '');
}

String fmtDur(int m) => '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String frDate(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

// Lecture sûre d'une valeur dans le JSON SimBrief ("fuel.taxi" par exemple)
String g(Map<String, dynamic>? m, String path) {
  dynamic v = m;
  for (final k in path.split('.')) {
    if (v is Map) {
      v = v[k];
    } else {
      return '';
    }
  }
  return (v == null || v is Map || v is List) ? '' : '$v';
}

String firstOf(Map<String, dynamic>? m, List<String> paths) {
  for (final s in paths) {
    final v = g(m, s);
    if (v.isNotEmpty) return v;
  }
  return '';
}

String hhmm(String epoch) {
  final s = int.tryParse(epoch);
  if (s == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} UTC';
}

const lists = <String, List<String>>{
  'Avant démarrage': [
    'Batterie ON', 'Feux anticollision ON', 'Carburant vérifié',
    'Freins de parking', 'Radio et transpondeur réglés', 'Altimètre calé'
  ],
  'Décollage': [
    'Volets réglés', 'Compensateur en position décollage', 'Mélange riche',
    'Piste dégagée', 'Transpondeur sur ALT', 'Puissance plein gaz'
  ],
  'Approche et atterrissage': [
    'ATIS écouté', 'Altimètre calé', 'Briefing d’approche fait',
    'Volets sortis', 'Train sorti (si rentrant)', 'Contrôle final'
  ],
};

class Home extends StatefulWidget {
  final Map<String, String> cfg;
  final void Function(String, String) setCfg;
  final SharedPreferences prefs;
  const Home({super.key, required this.cfg, required this.setCfg, required this.prefs});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  bool loading = false;
  List<Flight> flights = [];
  Set<String> checked = {};
  Map<String, dynamic>? plan;
  SharedPreferences get p => widget.prefs;

  @override
  void initState() {
    super.initState();
    final f = p.getString('flights');
    if (f != null) {
      try {
        flights = (jsonDecode(f) as List)
            .map((e) => Flight.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    checked = (p.getStringList('checks') ?? []).toSet();
    final pl = p.getString('plan');
    if (pl != null) {
      try {
        plan = (jsonDecode(pl) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    scheduleSync();
  }

  // Synchronise heures de vol, trajets favoris et SimBrief vers le profil en ligne
  Timer? _syncT;
  void scheduleSync() {
    _syncT?.cancel();
    _syncT = Timer(const Duration(milliseconds: 1500), syncProfile);
  }

  void syncProfile() {
    final c = <String, int>{};
    for (final f in flights) {
      final r = '${f.dep}-${f.arr}';
      c[r] = (c[r] ?? 0) + 1;
    }
    final top = (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => e.key)
        .toList();
    syncStats(flights.fold<int>(0, (s, f) => s + f.dur), top, widget.cfg['sb'] ?? '');
  }

  @override
  void didUpdateWidget(Home old) {
    super.didUpdateWidget(old);
    scheduleSync();
  }

  @override
  void dispose() {
    _syncT?.cancel();
    super.dispose();
  }

  void saveFlights() {
    p.setString('flights', jsonEncode(flights.map((f) => f.toJson()).toList()));
    scheduleSync();
  }

  void snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String pg(String path) => g(plan, path);

  Future<void> importPlan() async {
    final id = widget.cfg['sb']!.trim();
    if (id.isEmpty) {
      snack('Entre d’abord ton identifiant SimBrief dans Réglages.');
      setState(() => tab = 5);
      return;
    }
    setState(() => loading = true);
    try {
      final q = RegExp(r'^\d+$').hasMatch(id)
          ? 'userid=$id'
          : 'username=${Uri.encodeComponent(id)}';
      final r = await http
          .get(Uri.parse('https://www.simbrief.com/api/xml.fetcher.php?$q&json=1'))
          .timeout(const Duration(seconds: 25));
      final j = jsonDecode(r.body);
      if (j is Map && j['origin'] is Map) {
        plan = j.cast<String, dynamic>();
        p.setString('plan', r.body);
        tab = 2;
        snack('Plan de vol importé.');
      } else {
        final st = (j is Map && j['fetch'] is Map) ? '${j['fetch']['status']}' : '';
        snack(st.isNotEmpty ? 'SimBrief : $st' : 'Aucun plan de vol trouvé.');
      }
    } catch (_) {
      snack('Import impossible. Vérifie ta connexion et ton identifiant SimBrief.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> addFlight(
      {String dep0 = '', String arr0 = '', String avion0 = '', int? min0}) async {
    final dep = TextEditingController(text: dep0), arr = TextEditingController(text: arr0);
    final dur = TextEditingController(text: min0?.toString() ?? '');
    final avion = TextEditingController(text: avion0), note = TextEditingController();
    DateTime date = DateTime.now();
    String? err;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Nouveau vol',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: dep,
                          maxLength: 4,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                              labelText: 'Départ (OACI)', counterText: ''))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: arr,
                          maxLength: 4,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                              labelText: 'Arrivée (OACI)', counterText: ''))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100));
                            if (d != null) setS(() => date = d);
                          },
                          child: Text(fmtDate(date)))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: dur,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Durée (min)'))),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: avion,
                    decoration: const InputDecoration(labelText: 'Avion (A320, Cessna 172…)')),
                const SizedBox(height: 12),
                TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes')),
                if (err != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!, style: const TextStyle(color: Color(0xFFFF6B5E)))),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    final m = int.tryParse(dur.text.trim());
                    if (dep.text.trim().isEmpty ||
                        arr.text.trim().isEmpty ||
                        avion.text.trim().isEmpty ||
                        m == null ||
                        m <= 0) {
                      setS(() => err =
                          'Remplis le départ, l’arrivée, l’avion et une durée en minutes.');
                      return;
                    }
                    setState(() {
                      flights.add(Flight(
                          DateTime.now().millisecondsSinceEpoch,
                          dep.text.trim().toUpperCase(),
                          arr.text.trim().toUpperCase(),
                          isoDate(date),
                          m,
                          avion.text.trim(),
                          note.text.trim()));
                      tab = 1;
                    });
                    saveFlights();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Enregistrer le vol'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmer')),
        ],
      ),
    );
    return ok == true;
  }

  Widget stat(String v, String l) => Expanded(
        child: Card(
          elevation: 0,
          shape: cardShape,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Text(v,
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: kAccent)),
              Text(l, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget homePage() {
    final total = flights.fold<int>(0, (a, f) => a + f.dur);
    final aero = <String>{for (final f in flights) ...[f.dep, f.arr]};
    final name = widget.cfg['pseudo']!.trim();
    return ListView(padding: EdgeInsets.zero, children: [
      Container(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 24, 20, 28),
        decoration: const BoxDecoration(
            gradient: brand,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32))),
        child: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/logo.png', width: 64, height: 64)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AeroSimAPP',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
            Text(name.isEmpty ? 'Bon vol !' : 'Bon vol, $name',
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            stat('${flights.length}', 'vols'),
            stat(fmtDur(total), 'de vol'),
            stat('${aero.length}', 'aéroports'),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: loading ? null : importPlan,
            icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: const Text('Importer le plan de vol SimBrief'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          ),
          if (plan != null) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: cardShape,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Icon(Icons.flight_takeoff, color: kAccent),
                title: Text('${pg('origin.icao_code')} → ${pg('destination.icao_code')}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                subtitle: const Text('Dernier plan SimBrief importé'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => tab = 2),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget carnetPage() {
    final sorted = [...flights]..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    if (sorted.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'Aucun vol pour l’instant. Appuie sur « Ajouter un vol » ou importe un plan SimBrief.',
                  textAlign: TextAlign.center)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      for (final f in sorted)
        Card(
          elevation: 0,
          shape: cardShape,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            title: Text('${f.dep} → ${f.arr}',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${frDate(f.date)} · ${f.avion} · ${fmtDur(f.dur)}${f.note.isEmpty ? '' : '\n${f.note}'}'),
            isThreeLine: f.note.isNotEmpty,
            trailing: IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm('Supprimer ce vol ?', '${f.dep} → ${f.arr}, ${frDate(f.date)}')) {
                    setState(() => flights.removeWhere((x) => x.id == f.id));
                    saveFlights();
                  }
                }),
          ),
        ),
    ]);
  }

  Widget section(String title, List<List<String>> rows) {
    final r = rows.where((e) => e[1].isNotEmpty).toList();
    if (r.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: cardShape,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title,
              style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          for (final e in r)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: Text(e[0])),
                const SizedBox(width: 12),
                Text(e[1], style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget textCard(String title, String body) => body.isEmpty
      ? const SizedBox.shrink()
      : Card(
          elevation: 0,
          shape: cardShape,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              SelectableText(body, style: const TextStyle(height: 1.4)),
            ]),
          ),
        );

  Widget planPage() {
    if (plan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.flight_takeoff, size: 56, color: kAccent),
            const SizedBox(height: 12),
            const Text('Aucun plan importé',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
                'Génère un plan sur SimBrief, puis importe-le ici. Ton identifiant se règle dans Réglages.',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: loading ? null : importPlan,
                icon: const Icon(Icons.download),
                label: const Text('Importer le plan de vol SimBrief')),
          ]),
        ),
      );
    }
    final u = pg('params.units') == 'lbs' ? 'lb' : 'kg';
    String wt(String v) => v.isEmpty ? '' : '$v $u';
    final dep = pg('origin.icao_code'), arr = pg('destination.icao_code');
    final min = (int.tryParse(pg('times.est_time_enroute')) ?? 0) ~/ 60;
    final alt = int.tryParse(pg('general.initial_altitude'));
    final dist = pg('general.air_distance');
    final acft = [
      firstOf(plan, ['aircraft.icaocode', 'aircraft.icao_code']),
      pg('aircraft.reg')
    ].where((s) => s.isNotEmpty).join(' · ');
    final chips = [
      '${pg('general.icao_airline')}${pg('general.flight_number')}',
      acft,
      if (min > 0) fmtDur(min),
      if (dist.isNotEmpty) '$dist NM',
      if (alt != null) 'FL${(alt / 100).round()}',
      if (pg('general.costindex').isNotEmpty) 'CI ${pg('general.costindex')}',
    ].where((s) => s.isNotEmpty).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: brand, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$dep → $arr',
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${pg('origin.name')} → ${pg('destination.name')}',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final c in chips) Chip(label: Text(c)),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      section('Horaires et pistes', [
        ['Départ prévu', hhmm(pg('times.sched_out'))],
        ['Arrivée prévue', hhmm(pg('times.sched_in'))],
        ['Piste de départ', pg('origin.plan_rwy')],
        ['Piste d’arrivée', pg('destination.plan_rwy')],
        ['Dégagement', pg('alternate.icao_code')],
      ]),
      textCard('Route', pg('general.route')),
      section('Carburant', [
        ['Roulage', wt(pg('fuel.taxi'))],
        ['Trajet', wt(pg('fuel.enroute_burn'))],
        ['Réserve de route', wt(pg('fuel.contingency'))],
        ['Dégagement', wt(pg('fuel.alternate_burn'))],
        ['Réserve finale', wt(pg('fuel.reserve'))],
        ['Supplément', wt(pg('fuel.extra'))],
        ['Au décollage', wt(pg('fuel.plan_takeoff'))],
        ['Total au parking', wt(pg('fuel.plan_ramp'))],
      ]),
      section('Masses', [
        ['Passagers', pg('weights.pax_count')],
        ['Charge payante', wt(pg('weights.payload'))],
        ['ZFW', wt(pg('weights.est_zfw'))],
        ['TOW', wt(pg('weights.est_tow'))],
        ['LDW', wt(pg('weights.est_ldw'))],
      ]),
      textCard('METAR départ', pg('weather.orig_metar')),
      textCard('METAR arrivée', pg('weather.dest_metar')),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () => addFlight(
            dep0: dep, arr0: arr, avion0: pg('aircraft.name').isEmpty ? acft : pg('aircraft.name'),
            min0: min > 0 ? min : null),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter ce vol au carnet'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: loading ? null : importPlan,
        icon: const Icon(Icons.refresh),
        label: const Text('Réimporter le dernier plan'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    ]);
  }

  Widget checklistPage() {
    var li = 0;
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Padding(
          padding: EdgeInsets.all(4),
          child: Text('Listes générales : adapte-les à ton avion.')),
      for (final e in lists.entries) ...() {
        final idx = li++;
        return [
          Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(e.key,
                  style: TextStyle(color: kAccent, fontSize: 17, fontWeight: FontWeight.w700))),
          Card(
            elevation: 0,
            shape: cardShape,
            child: Column(children: [
              for (var i = 0; i < e.value.length; i++)
                CheckboxListTile(
                  value: checked.contains('$idx-$i'),
                  title: Text(e.value[i]),
                  onChanged: (v) {
                    setState(() =>
                        v == true ? checked.add('$idx-$i') : checked.remove('$idx-$i'));
                    p.setStringList('checks', checked.toList());
                  },
                ),
              TextButton(
                  onPressed: () {
                    setState(() => checked.removeWhere((k) => k.startsWith('$idx-')));
                    p.setStringList('checks', checked.toList());
                  },
                  child: const Text('Tout décocher')),
            ]),
          ),
        ];
      }(),
    ]);
  }

  Widget toolsPage() => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'Checklists'), Tab(text: 'Calculs')]),
          Expanded(child: TabBarView(children: [checklistPage(), const CalcPage()])),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    const titles = ['', 'Carnet de vol', 'Plan de vol', 'Outils', 'Communauté', 'Réglages'];
    final pages = [
      homePage(),
      carnetPage(),
      planPage(),
      toolsPage(),
      const SocialPage(),
      SettingsPage(
        cfg: widget.cfg,
        setCfg: widget.setCfg,
        onClear: () async {
          if (await confirm('Effacer le carnet ?', 'Tous tes vols enregistrés seront supprimés.')) {
            setState(() => flights.clear());
            saveFlights();
          }
        },
      ),
    ];
    return Scaffold(
      appBar: tab == 0
          ? null
          : AppBar(
              title: Text(titles[tab], style: const TextStyle(fontWeight: FontWeight.w700)),
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0),
      body: pages[tab],
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              onPressed: () => addFlight(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un vol'))
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Carnet'),
          NavigationDestination(icon: Icon(Icons.flight_takeoff), label: 'SimBrief'),
          NavigationDestination(icon: Icon(Icons.build_outlined), label: 'Outils'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Amis'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Réglages'),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final Map<String, String> cfg;
  final void Function(String, String) setCfg;
  final VoidCallback onClear;
  const SettingsPage({super.key, required this.cfg, required this.setCfg, required this.onClear});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final sb = TextEditingController(text: widget.cfg['sb']);

  Widget h(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(t, style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 16)));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      h('Compte'),
      Card(
        elevation: 0,
        shape: cardShape,
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text('@${widget.cfg['pseudo']}'),
            subtitle: const Text('Voir et modifier mon profil'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final uid = currentUid();
              if (uid != null) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ProfileView(uid: uid)));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: signOut,
          ),
        ]),
      ),
      h('SimBrief'),
      TextField(
          controller: sb,
          decoration: const InputDecoration(
              labelText: 'Identifiant SimBrief',
              helperText: 'Pilot ID (numéro) ou nom d’utilisateur, visible dans les réglages de ton compte SimBrief',
              helperMaxLines: 3),
          onChanged: (v) => widget.setCfg('sb', v.trim())),
      h('Apparence'),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: '0', label: Text('Système')),
          ButtonSegment(value: '1', label: Text('Clair')),
          ButtonSegment(value: '2', label: Text('Sombre')),
        ],
        selected: {widget.cfg['mode']!},
        onSelectionChanged: (s) => widget.setCfg('mode', s.first),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final e in accents.entries)
          ChoiceChip(
            label: Text(e.key),
            avatar: CircleAvatar(backgroundColor: e.value, radius: 8),
            selected: widget.cfg['accent'] == e.key,
            onSelected: (_) => widget.setCfg('accent', e.key),
          ),
      ]),
      h('Données'),
      OutlinedButton.icon(
          onPressed: widget.onClear,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Effacer le carnet de vol')),
      h('À propos'),
      const Text('AeroSimAPP · version 2.0'),
    ]);
  }
}

class CalcPage extends StatefulWidget {
  const CalcPage({super.key});
  @override
  State<CalcPage> createState() => _CalcPageState();
}

class _CalcPageState extends State<CalcPage> {
  final c = List.generate(6, (_) => TextEditingController());

  double? v(int i) => double.tryParse(c[i].text.trim().replaceAll(',', '.'));

  Widget field(int i, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
              controller: c[i],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label),
              onChanged: (_) => setState(() {})),
        ),
      );

  @override
  Widget build(BuildContext context) {
    String wind = 'Remplis les trois champs.';
    final wd = v(0), ws = v(1), rw = v(2);
    if (wd != null && ws != null && rw != null) {
      final a = (wd - rw) * math.pi / 180;
      final cross = ws * math.sin(a), head = ws * math.cos(a);
      final side = cross.abs() < 0.5 ? '' : (cross > 0 ? ' (de droite)' : ' (de gauche)');
      wind = 'Vent traversier : ${cross.abs().toStringAsFixed(0)} kt$side\n'
          '${head >= 0 ? 'Vent de face' : 'Vent arrière'} : ${head.abs().toStringAsFixed(0)} kt';
    }
    String desc = 'Remplis les trois champs (altitude actuelle supérieure à la cible).';
    final alt = v(3), tgt = v(4), gs = v(5);
    if (alt != null && tgt != null && gs != null && alt > tgt) {
      final d = (alt - tgt) / 1000 * 3;
      final vs = (gs * 5 / 50).round() * 50;
      desc = 'Commence la descente à ${d.toStringAsFixed(0)} NM du point visé.\n'
          'Taux de descente : environ $vs ft/min (pente de 3°).';
    }
    Widget title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(t,
            style: TextStyle(color: kAccent, fontSize: 17, fontWeight: FontWeight.w600)));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        title('Vent traversier'),
        Card(
          
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(children: [field(0, 'Vent : direction (°)'), field(1, 'Vent : force (kt)')]),
              Row(children: [field(2, 'Cap de la piste (°)')]),
              Padding(padding: const EdgeInsets.all(8), child: Text(wind, style: const TextStyle(fontSize: 16, height: 1.5))),
            ]),
          ),
        ),
        title('Début de descente'),
        Card(
          
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(children: [field(3, 'Altitude actuelle (ft)'), field(4, 'Altitude cible (ft)')]),
              Row(children: [field(5, 'Vitesse sol (kt)')]),
              Padding(padding: const EdgeInsets.all(8), child: Text(desc, style: const TextStyle(fontSize: 16, height: 1.5))),
            ]),
          ),
        ),
      ],
    );
  }
}
