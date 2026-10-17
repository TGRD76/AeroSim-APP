import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const CarnetApp());

const amber = Color(0xFFFFB44A);
const bg = Color(0xFF0C1118);
const panel = Color(0xFF141C28);
const mute = Color(0xFF8A97A8);

class CarnetApp extends StatelessWidget {
  const CarnetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carnet de vol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
            primary: amber, onPrimary: Color(0xFF1A1205), surface: panel),
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const Home(),
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
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  List<Flight> flights = [];
  Set<String> checked = {};
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      prefs = p;
      final f = p.getString('flights');
      if (f != null) {
        flights = (jsonDecode(f) as List)
            .map((e) => Flight.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      checked = (p.getStringList('checks') ?? []).toSet();
      setState(() {});
    });
  }

  void saveFlights() =>
      prefs?.setString('flights', jsonEncode(flights.map((f) => f.toJson()).toList()));
  void saveChecks() => prefs?.setStringList('checks', checked.toList());

  Future<void> addFlight() async {
    final dep = TextEditingController(), arr = TextEditingController();
    final dur = TextEditingController(), avion = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    String? err;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Nouveau vol',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
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
                          decoration: const InputDecoration(
                              labelText: 'Durée (min)'))),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: avion,
                    decoration: const InputDecoration(
                        labelText: 'Avion (Cessna 172, A320…)')),
                const SizedBox(height: 12),
                TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes')),
                if (err != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!,
                          style: const TextStyle(color: Color(0xFFFF6B5E)))),
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

  Future<void> deleteFlight(Flight f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce vol ?'),
        content: Text('${f.dep} → ${f.arr}, ${frDate(f.date)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => flights.removeWhere((x) => x.id == f.id));
      saveFlights();
    }
  }

  Widget stat(String v, String l) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: panel, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 24, color: amber, fontWeight: FontWeight.w600)),
            Text(l, style: const TextStyle(color: mute, fontSize: 12)),
          ]),
        ),
      );

  Widget carnetPage() {
    final total = flights.fold<int>(0, (a, f) => a + f.dur);
    final aero = <String>{for (final f in flights) ...[f.dep, f.arr]};
    final sorted = [...flights]..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Row(children: [
          stat('${flights.length}', 'vols'),
          stat(fmtDur(total), 'de vol'),
          stat('${aero.length}', 'aéroports'),
        ]),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'Aucun vol pour l’instant. Appuie sur « Ajouter un vol » pour enregistrer le premier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mute))),
        for (final f in sorted)
          Card(
            color: panel,
            child: ListTile(
              title: Text('${f.dep} → ${f.arr}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${frDate(f.date)} · ${f.avion} · ${fmtDur(f.dur)}${f.note.isEmpty ? '' : '\n${f.note}'}'),
              isThreeLine: f.note.isNotEmpty,
              trailing: IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => deleteFlight(f)),
            ),
          ),
      ],
    );
  }

  Widget checklistPage() {
    var li = 0;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Listes générales : adapte-les à ton avion.',
            style: TextStyle(color: mute)),
        for (final e in lists.entries) ...() {
          final idx = li++;
          return [
            Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text(e.key,
                    style: const TextStyle(
                        color: amber, fontSize: 17, fontWeight: FontWeight.w600))),
            Card(
              color: panel,
              child: Column(children: [
                for (var i = 0; i < e.value.length; i++)
                  CheckboxListTile(
                    value: checked.contains('$idx-$i'),
                    title: Text(e.value[i]),
                    onChanged: (v) {
                      setState(() => v == true
                          ? checked.add('$idx-$i')
                          : checked.remove('$idx-$i'));
                      saveChecks();
                    },
                  ),
                TextButton(
                    onPressed: () {
                      setState(() => checked.removeWhere((k) => k.startsWith('$idx-')));
                      saveChecks();
                    },
                    child: const Text('Tout décocher')),
              ]),
            ),
          ];
        }(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [carnetPage(), checklistPage(), const CalcPage()];
    const titles = ['Carnet de vol', 'Checklists', 'Calculs'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[tab]), backgroundColor: bg),
      body: pages[tab],
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: addFlight,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un vol'))
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Carnet'),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Checklists'),
          NavigationDestination(icon: Icon(Icons.calculate_outlined), label: 'Calculs'),
        ],
      ),
    );
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
            style: const TextStyle(color: amber, fontSize: 17, fontWeight: FontWeight.w600)));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        title('Vent traversier'),
        Card(
          color: panel,
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
          color: panel,
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
