import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../exemples.dart';
import '../outils/image_stub.dart' if (dart.library.js_interop) '../outils/image_web.dart';
import '../services/depot_echeances.dart';
import '../services/lecteur_courrier.dart';
import '../theme.dart';
import '../widgets/carte_cliquable.dart';
import 'verification.dart';

/// Picking or reading a file can fail on a phone (permission, a huge photo, browser quirks): say so, never stay
/// silent.
const _fichierIllisible = 'Impossible d\'ouvrir ce fichier. Réessaie, ou colle le texte du courrier.';

/// After this, the reading screen says the service is waking up.
const attenteLente = Duration(seconds: 8);

const _typesFichier = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
};

class EcranAjout extends StatefulWidget {
  const EcranAjout({super.key, required this.depot, required this.lecteur, required this.maintenant});

  final DepotEcheances depot;
  final LecteurCourrier lecteur;
  final DateTime Function() maintenant;

  @override
  State<EcranAjout> createState() => _EcranAjoutState();
}

class _EcranAjoutState extends State<EcranAjout> {
  final _texte = TextEditingController();
  final _defilement = ScrollController();
  bool _enCours = false;
  bool _lent = false;
  Timer? _minuteurLent;
  bool _texteOuvert = false;
  String? _erreur;

  @override
  void dispose() {
    _minuteurLent?.cancel();
    _texte.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _lire(CourrierAEnvoyer courrier) async {
    setState(() {
      _enCours = true;
      _lent = false;
      _erreur = null;
    });
    // The free backend sleeps when idle and takes about a minute to wake up: say so instead of looking stuck.
    _minuteurLent = Timer(attenteLente, () {
      if (mounted) setState(() => _lent = true);
    });
    try {
      final lecture = await widget.lecteur.lire(courrier).whenComplete(() => _minuteurLent?.cancel());
      if (!mounted) return;
      final enregistree = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EcranVerification(lecture: lecture, depot: widget.depot, maintenant: widget.maintenant),
        ),
      );
      if (enregistree == true && mounted) Navigator.of(context).pop(true);
    } on LectureImpossible catch (e) {
      if (mounted) _signaler(e.message);
    } catch (_) {
      // Whatever else went wrong, the user must see that the reading stopped.
      if (mounted) _signaler('La lecture a échoué. Réessaie dans un instant.');
    } finally {
      _minuteurLent?.cancel();
      if (mounted) {
        setState(() {
          _enCours = false;
          _lent = false;
        });
      }
    }
  }

  /// The message sits at the top: scroll up to it, the user may have tapped an example at the bottom.
  void _signaler(String message) {
    setState(() => _erreur = message);
    if (_defilement.hasClients) {
      _defilement.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Picking or reading a file can throw on a phone: any failure becomes a message, never a silent screen.
  /// `choisir` returns null when the user cancels.
  Future<void> _lireFichier(Future<CourrierFichier?> Function() choisir) async {
    final CourrierFichier? courrier;
    try {
      courrier = await choisir();
    } catch (_) {
      if (mounted) _signaler(_fichierIllisible);
      return;
    }
    if (courrier != null && mounted) await _lire(courrier);
  }

  Future<void> _importer() => _lireFichier(() async {
    final fichier = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: _typesFichier.keys.toList());
    if (fichier == null) return null;
    final type = _typesFichier[fichier.extension?.toLowerCase()];
    if (type == null) {
      if (mounted) _signaler('Choisis un PDF ou une image (PNG, JPEG, WebP).');
      return null;
    }
    final octets = await fichier.readAsBytes();
    // A phone photo is often 5-12 MB: shrink it in the browser (readable, faster, no GPS metadata).
    final reduite = type.startsWith('image/') ? await reduireImage(octets) : null;
    return reduite == null
        ? CourrierFichier(mediaType: type, octets: octets)
        : CourrierFichier(mediaType: 'image/jpeg', octets: reduite);
  });

  Future<void> _photographier() => _lireFichier(() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 80);
    return photo == null ? null : CourrierFichier(mediaType: 'image/jpeg', octets: await photo.readAsBytes());
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un courrier')),
      body: SafeArea(
        child: Column(
          children: [
            if (_enCours) const LinearProgressIndicator(backgroundColor: Couleurs.corailPale),
            Expanded(
              child: AbsorbPointer(
                absorbing: _enCours,
                child: ListView(
                  controller: _defilement,
                  padding: const EdgeInsets.fromLTRB(Espaces.l, Espaces.s, Espaces.l, Espaces.l),
                  children: [
                    Text(
                      _enCours
                          ? (_lent ? 'Le service se réveille, ça peut prendre une minute…' : 'Je lis ton courrier…')
                          : 'Pli lit le courrier et te propose l\'échéance. Pli n\'enregistre pas le courrier : '
                                'seule l\'échéance que tu valides est gardée.',
                      style: Textes.corps.copyWith(color: Couleurs.encreDouce),
                    ),
                    if (_erreur != null) ...[const SizedBox(height: Espaces.m), _Alerte(texte: _erreur!)],
                    const SizedBox(height: Espaces.l),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!kIsWeb)
                          _Choix(
                            emoji: '📸',
                            titre: 'Prendre une photo',
                            detail: 'Le courrier à plat, bien éclairé',
                            onTap: _photographier,
                          ),
                        _Choix(
                          emoji: '📄',
                          titre: 'Importer un PDF ou une image',
                          detail: '5 Mo maximum',
                          onTap: _importer,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Choix(
                              emoji: '📋',
                              titre: 'Coller le texte',
                              detail: 'Depuis un mail ou un espace en ligne',
                              onTap: () => setState(() => _texteOuvert = !_texteOuvert),
                            ),
                            if (_texteOuvert)
                              Padding(
                                padding: const EdgeInsets.only(top: Espaces.m),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      controller: _texte,
                                      minLines: 5,
                                      maxLines: 12,
                                      maxLength: 50000,
                                      decoration: const InputDecoration(labelText: 'Texte du courrier'),
                                    ),
                                    const SizedBox(height: Espaces.s),
                                    FilledButton(
                                      onPressed: () {
                                        if (_texte.text.trim().isEmpty) {
                                          setState(() => _erreur = 'Colle d\'abord le texte du courrier.');
                                          return;
                                        }
                                        _lire(CourrierTexte(_texte.text));
                                      },
                                      child: const Text('Lire ce texte'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: Espaces.l),
                    const Text('Pas de courrier sous la main ?', style: Textes.section),
                    const SizedBox(height: Espaces.xs),
                    const Text('Essaie avec un courrier fictif.', style: Textes.discret),
                    const SizedBox(height: Espaces.m),
                    for (final exemple in exemples)
                      _Choix(
                        emoji: '✉️',
                        titre: exemple.titre,
                        detail: 'Courrier fictif',
                        onTap: () => _lire(CourrierTexte(exemple.texte)),
                      ),
                  ],
                ),
              ),
            ),
            if (Config.demo)
              const Padding(
                padding: EdgeInsets.fromLTRB(Espaces.m, Espaces.s, Espaces.m, Espaces.m),
                child: Text(
                  'Démo : la lecture réelle passe par le backend avec Claude.',
                  style: Textes.discret,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An option as a Buddy-style card: an emoji in a soft circle, a title and a hint.
class _Choix extends StatelessWidget {
  const _Choix({required this.emoji, required this.titre, required this.detail, required this.onTap});

  final String emoji;
  final String titre;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CarteCliquable(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Couleurs.corailPale, shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: Espaces.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: Textes.ligne),
                Text(detail, style: Textes.discret),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Couleurs.encreDouce),
        ],
      ),
    );
  }
}

class _Alerte extends StatelessWidget {
  const _Alerte({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Espaces.m),
        decoration: decorationCarte(fond: Couleurs.corailPale, bord: Couleurs.corailPale),
        child: Text(texte, style: Textes.corps),
      ),
    );
  }
}
