import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_config.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;
const _spinner = Loading();

class Loading extends StatefulWidget {
  final String label;
  const Loading([this.label = '']);
  @override
  State<Loading> createState() => _LoadingState();
}

class _LoadingState extends State<Loading> {
  bool slow = false;
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => slow = true);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            if (widget.label.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(widget.label, textAlign: TextAlign.center),
            ],
            if (slow) ...[
              const SizedBox(height: 24),
              const Text('Le chargement est long. Vérifie ta connexion internet.',
                  textAlign: TextAlign.center),
              TextButton(onPressed: signOut, child: const Text('Se déconnecter')),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final Object error;
  const _ErrorPage(this.error);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('Une erreur est survenue', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            SelectableText('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: signOut, child: const Text('Se déconnecter')),
          ]),
        ),
      ),
    );
  }
}

String _dur(int m) => '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';

String _authErr(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou mot de passe incorrect.';
      case 'email-already-in-use':
        return 'Un compte existe déjà avec cet e-mail.';
      case 'weak-password':
        return 'Mot de passe trop court (6 caractères minimum).';
      case 'network-request-failed':
        return 'Pas de connexion internet.';
      default:
        return 'Erreur : ${e.code}';
    }
  }
  return 'Erreur : $e';
}

String? currentUid() => _auth.currentUser?.uid;

Future<void> signOut() async {
  _lastSig = null;
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
  await _auth.signOut();
}

Future<void> updateProfile(Map<String, dynamic> data) async {
  final u = _auth.currentUser;
  if (u == null) return;
  await _db.collection('users').doc(u.uid).set(data, SetOptions(merge: true));
}

String? _lastSig;
// Envoie heures de vol, trajets favoris et identifiant SimBrief sur le profil.
Future<void> syncStats(int minutes, List<String> routes, String simbrief) async {
  final sig = '$minutes|${routes.join(',')}|$simbrief';
  if (sig == _lastSig) return;
  try {
    await updateProfile({'minutes': minutes, 'favRoutes': routes, 'simbrief': simbrief});
    _lastSig = sig;
  } catch (_) {}
}

/// Renvoie un message d'erreur, ou null si l'ami a été ajouté.
Future<String?> addFriend(String raw) async {
  final me = currentUid();
  if (me == null) return 'Non connecté.';
  final name = raw.trim().toLowerCase().replaceAll('@', '');
  if (name.isEmpty) return 'Entre un nom d’utilisateur.';
  try {
    final s = await _db.collection('usernames').doc(name).get();
    if (!s.exists) return 'Aucun pilote avec ce nom.';
    final uid = s.data()!['uid'] as String;
    if (uid == me) return 'C’est ton propre compte !';
    await _db
        .collection('users')
        .doc(me)
        .collection('friends')
        .doc(uid)
        .set({'username': name, 'added': FieldValue.serverTimestamp()});
    return null;
  } catch (e) {
    return 'Impossible d’ajouter cet ami. Vérifie ta connexion.';
  }
}

Future<void> removeFriend(String uid) async {
  final me = currentUid();
  if (me == null) return;
  await _db.collection('users').doc(me).collection('friends').doc(uid).delete();
}

// ───────────────────────── Porte d'entrée (connexion automatique)

class AuthGate extends StatelessWidget {
  final Widget child;
  final void Function(String username) onUsername;
  const AuthGate({super.key, required this.child, required this.onUsername});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (c, s) {
        if (s.hasError) return _ErrorPage(s.error!);
        if (s.connectionState == ConnectionState.waiting) return const Loading('Connexion au compte…');
        final u = s.data;
        if (u == null) return const LoginPage();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(u.uid),
          stream: _db.collection('users').doc(u.uid).snapshots(),
          builder: (c, d) {
            if (d.hasError) return _ErrorPage(d.error!);
            if (!d.hasData) return const Loading('Chargement du profil…');
            final snap = d.data!;
            final name = snap.data()?['username'] as String?;
            if (name == null || name.isEmpty) {
              if (snap.metadata.isFromCache) return _spinner;
              return UsernamePage(uid: u.uid);
            }
            onUsername(name);
            return child;
          },
        );
      },
    );
  }
}

// ───────────────────────── Connexion / inscription

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  bool register = false, busy = false, hide = true;
  String? err;

  Future<void> run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await f();
    } catch (x) {
      err = _authErr(x);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> submit() => run(() async {
        final e = email.text.trim(), p = pass.text;
        if (register) {
          await _auth.createUserWithEmailAndPassword(email: e, password: p);
        } else {
          await _auth.signInWithEmailAndPassword(email: e, password: p);
        }
      });

  Future<void> google() => run(() async {
        try {
          final g = await GoogleSignIn(serverClientId: googleWebClientId).signIn();
          if (g == null) return;
          final a = await g.authentication;
          await _auth.signInWithCredential(
              GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken));
        } on FirebaseAuthException {
          rethrow;
        } catch (_) {
          throw 'Connexion Google impossible (vérifie l’empreinte SHA-1 dans Firebase).';
        }
      });

  Future<void> reset() async {
    final e = email.text.trim();
    if (e.isEmpty) {
      setState(() => err = 'Entre ton e-mail puis appuie sur « Mot de passe oublié ».');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('E-mail de réinitialisation envoyé.')));
      }
    } catch (x) {
      setState(() => err = _authErr(x));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/logo.png', height: 96))),
              const SizedBox(height: 16),
              const Text('AeroSimAPP',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(register ? 'Crée ton compte pilote' : 'Connecte-toi pour continuer',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Adresse e-mail')),
              const SizedBox(height: 12),
              TextField(
                  controller: pass,
                  obscureText: hide,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      suffixIcon: IconButton(
                          icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => hide = !hide)))),
              if (err != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: busy ? null : submit,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: busy
                          ? const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(register ? 'S’inscrire' : 'Se connecter'))),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: busy ? null : google,
                  icon: const Icon(Icons.g_mobiledata, size: 32),
                  label: const Padding(
                      padding: EdgeInsets.all(8), child: Text('Continuer avec Google'))),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: busy ? null : () => setState(() => register = !register),
                  child: Text(register
                      ? 'J’ai déjà un compte'
                      : 'Pas de compte ? Créer un compte')),
              if (!register) TextButton(onPressed: reset, child: const Text('Mot de passe oublié')),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Choix du nom d'utilisateur (une seule fois)

class UsernamePage extends StatefulWidget {
  final String uid;
  const UsernamePage({super.key, required this.uid});
  @override
  State<UsernamePage> createState() => _UsernamePageState();
}

class _UsernamePageState extends State<UsernamePage> {
  final c = TextEditingController();
  bool busy = false;
  String? err;

  Future<void> save() async {
    final name = c.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(name)) {
      setState(() => err = '3 à 20 caractères : lettres, chiffres ou _ (sans espace).');
      return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final uref = _db.collection('usernames').doc(name);
      await _db.runTransaction((t) async {
        if ((await t.get(uref)).exists) throw 'taken';
        t.set(uref, {'uid': widget.uid});
        t.set(
            _db.collection('users').doc(widget.uid),
            {
              'username': name,
              'photo': '',
              'discord': '',
              'volanta': '',
              'simbrief': '',
              'minutes': 0,
              'favRoutes': <String>[],
              'created': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      });
    } catch (e) {
      err = e == 'taken' ? 'Ce nom est déjà pris.' : 'Impossible d’enregistrer. Vérifie ta connexion.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          actions: [TextButton(onPressed: signOut, child: const Text('Se déconnecter'))]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Choisis ton nom d’utilisateur',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Tes amis pourront t’ajouter avec ce nom. Tu ne pourras pas le changer ensuite.'),
        const SizedBox(height: 20),
        TextField(
            controller: c,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Nom d’utilisateur', prefixText: '@', errorText: err)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: busy ? null : save,
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Continuer'))),
      ]),
    );
  }
}

// ───────────────────────── Avatar

class Avatar extends StatelessWidget {
  final String photo, name;
  final double r;
  const Avatar({super.key, required this.photo, required this.name, this.r = 22});

  @override
  Widget build(BuildContext context) {
    ImageProvider? img;
    if (photo.isNotEmpty) {
      try {
        img = MemoryImage(base64Decode(photo));
      } catch (_) {}
    }
    return CircleAvatar(
        radius: r,
        backgroundImage: img,
        child: img == null
            ? Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: TextStyle(fontSize: r * 0.9, fontWeight: FontWeight.w700))
            : null);
  }
}

// ───────────────────────── Onglet Amis

class SocialPage extends StatefulWidget {
  const SocialPage({super.key});
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  final c = TextEditingController();
  String? msg;
  bool busy = false;

  Future<void> add() async {
    setState(() => busy = true);
    final e = await addFriend(c.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      msg = e ?? 'Ami ajouté !';
      if (e == null) c.clear();
    });
  }

  void open(String uid) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileView(uid: uid)));

  @override
  Widget build(BuildContext context) {
    final me = currentUid()!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _UserTile(uid: me, onTap: () => open(me), mine: true),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: TextField(
                controller: c,
                autocorrect: false,
                onSubmitted: (_) => add(),
                decoration: const InputDecoration(
                    labelText: 'Ajouter un ami', prefixText: '@', hintText: 'nom d’utilisateur'))),
        const SizedBox(width: 8),
        IconButton.filled(
            onPressed: busy ? null : add, icon: const Icon(Icons.person_add_alt_1)),
      ]),
      if (msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!)),
      Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text('Mes amis',
              style: TextStyle(color: kAccentOf(context), fontWeight: FontWeight.w700, fontSize: 16))),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(me).collection('friends').snapshots(),
        builder: (c, s) {
          final docs = s.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun ami pour l’instant. Ajoute quelqu’un avec son nom d’utilisateur.'));
          }
          return Column(children: [
            for (final d in docs)
              _UserTile(
                  uid: d.id,
                  onTap: () => open(d.id),
                  onRemove: () async {
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (x) => AlertDialog(
                              title: Text('Retirer @${d.data()['username']} ?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(x, false),
                                    child: const Text('Annuler')),
                                TextButton(
                                    onPressed: () => Navigator.pop(x, true),
                                    child: const Text('Retirer')),
                              ],
                            ));
                    if (ok == true) removeFriend(d.id);
                  }),
          ]);
        },
      ),
    ]);
  }
}

Color kAccentOf(BuildContext c) => Theme.of(c).colorScheme.primary;

class _UserTile extends StatelessWidget {
  final String uid;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool mine;
  const _UserTile({required this.uid, required this.onTap, this.onRemove, this.mine = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').doc(uid).snapshots(),
      builder: (c, s) {
        final d = s.data?.data();
        if (d == null) return const ListTile(title: Text('…'));
        final name = (d['username'] ?? '') as String;
        return Card(
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
          child: ListTile(
            leading: Avatar(photo: (d['photo'] ?? '') as String, name: name),
            title: Text(mine ? '@$name (moi)' : '@$name',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${_dur((d['minutes'] ?? 0) as int)} de vol'),
            trailing: onRemove == null
                ? const Icon(Icons.chevron_right)
                : IconButton(icon: const Icon(Icons.person_remove_outlined), onPressed: onRemove),
            onTap: onTap,
          ),
        );
      },
    );
  }
}

// ───────────────────────── Profil (le sien ou celui d'un ami)

class ProfileView extends StatelessWidget {
  final String uid;
  const ProfileView({super.key, required this.uid});

  Widget badge(IconData i, String label, bool ok) => Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.cancel_outlined,
          size: 18, color: ok ? Colors.green : Colors.grey),
      label: Text(label));

  Widget info(IconData i, String t, String v) => Card(
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      child: ListTile(leading: Icon(i), title: Text(t), subtitle: Text(v)));

  @override
  Widget build(BuildContext context) {
    final mine = uid == currentUid();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').doc(uid).snapshots(),
      builder: (c, s) {
        final d = s.data?.data();
        if (d == null) return _spinner;
        final name = (d['username'] ?? '') as String;
        final discord = (d['discord'] ?? '') as String;
        final sb = (d['simbrief'] ?? '') as String;
        final vo = (d['volanta'] ?? '') as String;
        final routes = ((d['favRoutes'] ?? []) as List).cast<String>();
        return Scaffold(
          appBar: AppBar(
            title: Text('@$name'),
            actions: [
              if (mine)
                IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ProfileEditPage(data: d)))),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: Avatar(photo: (d['photo'] ?? '') as String, name: name, r: 56)),
            const SizedBox(height: 12),
            Center(
                child: Text('@$name',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
              badge(Icons.flight_takeoff, 'SimBrief', sb.isNotEmpty),
              badge(Icons.radar, 'Volanta', vo.isNotEmpty),
            ]),
            const SizedBox(height: 12),
            info(Icons.timer_outlined, 'Heures de vol', _dur((d['minutes'] ?? 0) as int)),
            if (sb.isNotEmpty) info(Icons.flight_takeoff, 'SimBrief', sb),
            if (vo.isNotEmpty) info(Icons.radar, 'Volanta', vo),
            info(Icons.chat_bubble_outline, 'Discord', discord.isEmpty ? 'Non renseigné' : discord),
            info(Icons.route, 'Trajets favoris',
                routes.isEmpty ? 'Aucun vol enregistré' : routes.join('\n')),
          ]),
        );
      },
    );
  }
}

// ───────────────────────── Modifier son profil

class ProfileEditPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const ProfileEditPage({super.key, required this.data});
  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final discord = TextEditingController(text: widget.data['discord'] ?? '');
  late final volanta = TextEditingController(text: widget.data['volanta'] ?? '');
  late String photo = widget.data['photo'] ?? '';
  bool busy = false;

  Future<void> pick() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 70);
    if (x == null) return;
    final b = base64Encode(await x.readAsBytes());
    await updateProfile({'photo': b});
    if (mounted) setState(() => photo = b);
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await updateProfile({'discord': discord.text.trim(), 'volanta': volanta.text.trim()});
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enregistrement impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.data['username'] ?? '') as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
            child: GestureDetector(
                onTap: pick,
                child: Stack(children: [
                  Avatar(photo: photo, name: name, r: 56),
                  const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(radius: 16, child: Icon(Icons.camera_alt, size: 18))),
                ]))),
        const SizedBox(height: 8),
        Center(child: Text('@$name')),
        const SizedBox(height: 24),
        TextField(
            controller: discord,
            decoration: const InputDecoration(
                labelText: 'Pseudo Discord', prefixIcon: Icon(Icons.chat_bubble_outline))),
        const SizedBox(height: 16),
        TextField(
            controller: volanta,
            decoration: const InputDecoration(
                labelText: 'Nom d’utilisateur Volanta',
                helperText: 'Affiché sur ton profil. Ton identifiant SimBrief se règle dans Réglages.',
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.radar))),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy ? null : save,
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Enregistrer'))),
      ]),
    );
  }
}
