import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../exemples.dart';
import '../modeles/echeance.dart';
import '../modeles/lecture.dart';
import '../outils/image_natif.dart' if (dart.library.js_interop) '../outils/image_web.dart';
import '../outils/selection_stub.dart' if (dart.library.js_interop) '../outils/selection_web.dart';
import '../services/depot_echeances.dart';
import '../services/lecteur_courrier.dart';
import '../theme.dart';
import '../widgets/choix.dart';
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

/// The ways to add a letter, over the list: returns the saved deadline, null if the user closed the sheet.
Future<Echeance?> ouvrirAjout(
  BuildContext context, {
  required DepotEcheances depot,
  required LecteurCourrier lecteur,
  required DateTime Function() maintenant,
}) => showModalBottomSheet<Echeance>(
  context: context,
  backgroundColor: Couleurs.fond,
  showDragHandle: true,
  // The text field and its keyboard can need more than the default 9/16 of the screen.
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FeuilleAjout(depot: depot, lecteur: lecteur, maintenant: maintenant),
);

/// Closing the sheet during a reading cancels it for the user: the answer is dropped.
class FeuilleAjout extends StatefulWidget {
  const FeuilleAjout({super.key, required this.depot, required this.lecteur, required this.maintenant});

  final DepotEcheances depot;
  final LecteurCourrier lecteur;
  final DateTime Function() maintenant;

  @override
  State<FeuilleAjout> createState() => _FeuilleAjoutState();
}

class _FeuilleAjoutState extends State<FeuilleAjout> {
  final _texte = TextEditingController();
  final _defilement = ScrollController();
  bool _enCours = false;
  bool _lent = false;
  Timer? _minuteurLent;
  bool _texteOuvert = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    unawaited(widget.lecteur.reveiller());
  }

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
      if (mounted) await _verifier(lecture);
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

  Future<void> _verifier(Lecture lecture) async {
    final enregistree = await Navigator.of(context).push<Echeance>(
      MaterialPageRoute(
        builder: (_) => EcranVerification(lecture: lecture, depot: widget.depot, maintenant: widget.maintenant),
      ),
    );
    if (enregistree != null && mounted) Navigator.of(context).pop(enregistree);
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
    final fichier = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _typesFichier.keys.toList(),
      webOptions: optionsSelection,
    );
    if (fichier == null) return null;
    final type = _typesFichier[fichier.extension?.toLowerCase()];
    if (type == null) {
      if (mounted) _signaler('Choisis un PDF ou une image (PNG, JPEG, WebP).');
      return null;
    }
    final octets = await fichier.readAsBytes();
    // A phone photo is often 5-12 MB: shrink it before sending (readable, faster, no GPS metadata).
    final reduite = type.startsWith('image/') ? await reduireImage(octets) : null;
    return reduite == null
        ? CourrierFichier(mediaType: type, octets: octets)
        : CourrierFichier(mediaType: 'image/jpeg', octets: reduite);
  });

  /// The picker shrinks the photo. A screenshot can stay a PNG: the backend reads the real type from the bytes.
  Future<void> _choisirImage(ImageSource source) => _lireFichier(() async {
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 80);
    return photo == null ? null : CourrierFichier(mediaType: 'image/jpeg', octets: await photo.readAsBytes());
  });

  String get _consigne {
    if (_enCours) return _lent ? 'Le service se réveille, ça peut prendre une minute…' : 'Je lis ton courrier…';
    if (Config.demo) {
      return 'Pli lit le courrier et te propose l\'échéance. Pli n\'enregistre pas le courrier : '
          'seule l\'échéance que tu valides est gardée.';
    }
    return 'Pli envoie le courrier à Claude (Anthropic) pour le lire et ne le garde pas : '
        'seule l\'échéance que tu valides est enregistrée.';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Above the keyboard when the text field is open.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_enCours) const LinearProgressIndicator(backgroundColor: Couleurs.corailPale),
            Flexible(
              child: AbsorbPointer(
                absorbing: _enCours,
                child: ListView(
                  controller: _defilement,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(Espaces.l, Espaces.s, Espaces.l, Espaces.m),
                  children: [
                    const Text('Ajouter un courrier', style: Textes.section),
                    const SizedBox(height: Espaces.xs),
                    Text(_consigne, style: Textes.discret),
                    if (_erreur != null) ...[const SizedBox(height: Espaces.m), _Alerte(texte: _erreur!)],
                    const SizedBox(height: Espaces.m),
                    if (!kIsWeb) ...[
                      Choix(
                        emoji: '📸',
                        titre: 'Prendre une photo',
                        detail: 'Le courrier à plat, bien éclairé',
                        onTap: () => _choisirImage(ImageSource.camera),
                      ),
                      Choix(
                        emoji: '🖼️',
                        titre: 'Choisir dans mes photos',
                        detail: 'Une photo ou une capture d\'écran',
                        onTap: () => _choisirImage(ImageSource.gallery),
                      ),
                    ],
                    Choix(
                      emoji: '📄',
                      titre: kIsWeb ? 'Importer un PDF ou une image' : 'Importer un fichier',
                      detail: kIsWeb ? '5 Mo maximum' : 'PDF ou image, 5 Mo maximum',
                      onTap: _importer,
                    ),
                    Choix(
                      emoji: '📋',
                      titre: 'Coller le texte',
                      detail: 'Depuis un mail ou un espace en ligne',
                      onTap: () => setState(() => _texteOuvert = !_texteOuvert),
                    ),
                    if (_texteOuvert) ...[
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
                            _signaler('Colle d\'abord le texte du courrier.');
                            return;
                          }
                          _lire(CourrierTexte(_texte.text));
                        },
                        child: const Text('Lire ce texte'),
                      ),
                      const SizedBox(height: Espaces.m),
                    ],
                    Choix(
                      emoji: '✏️',
                      titre: 'Saisir à la main',
                      detail: 'Si la lecture ne marche pas',
                      onTap: () => _verifier(Lecture.manuelle()),
                    ),
                    // The demo only reads these. On the real app, each one would be a paid reading.
                    if (Config.demo) ...[
                      const SizedBox(height: Espaces.s),
                      const Text('Pas de courrier sous la main ?', style: Textes.section),
                      const SizedBox(height: Espaces.xs),
                      const Text('Essaie avec un courrier fictif.', style: Textes.discret),
                      const SizedBox(height: Espaces.m),
                      for (final exemple in exemples)
                        Choix(
                          emoji: '✉️',
                          titre: exemple.titre,
                          detail: 'Courrier fictif',
                          onTap: () => _lire(CourrierTexte(exemple.texte)),
                        ),
                      const Text(
                        'Démo : la lecture réelle passe par le backend avec Claude.',
                        style: Textes.discret,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
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
