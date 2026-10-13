import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../exemples.dart';
import '../services/depot_echeances.dart';
import '../services/lecteur_courrier.dart';
import '../theme.dart';
import '../widgets/feuille_pliee.dart';
import 'verification.dart';

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
  bool _texteOuvert = false;
  String? _erreur;

  @override
  void dispose() {
    _texte.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _lire(CourrierAEnvoyer courrier) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final lecture = await widget.lecteur.lire(courrier);
      if (!mounted) return;
      final enregistree = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EcranVerification(lecture: lecture, depot: widget.depot, maintenant: widget.maintenant),
        ),
      );
      if (enregistree == true && mounted) Navigator.of(context).pop(true);
    } on LectureImpossible catch (e) {
      if (mounted) _signaler(e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// The message sits at the top: scroll up to it, the user may have tapped an example at the bottom.
  void _signaler(String message) {
    setState(() => _erreur = message);
    if (_defilement.hasClients) {
      _defilement.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _importer() async {
    final fichier = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: _typesFichier.keys.toList());
    if (fichier == null) return;
    final type = _typesFichier[fichier.extension?.toLowerCase()];
    if (type == null) {
      _signaler('Choisis un PDF ou une image (PNG, JPEG, WebP).');
      return;
    }
    await _lire(CourrierFichier(mediaType: type, octets: await fichier.readAsBytes()));
  }

  Future<void> _photographier() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 80);
    if (photo == null) return;
    await _lire(CourrierFichier(mediaType: 'image/jpeg', octets: await photo.readAsBytes()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un courrier')),
      body: SafeArea(
        child: Column(
          children: [
            if (_enCours) const LinearProgressIndicator(color: Couleurs.tampon, backgroundColor: Couleurs.pli),
            Expanded(
              child: AbsorbPointer(
                absorbing: _enCours,
                child: ListView(
                  controller: _defilement,
                  padding: const EdgeInsets.all(Espaces.m),
                  children: [
                    Text(
                      _enCours
                          ? 'Je lis ton courrier…'
                          : 'Pli lit le courrier et te propose l\'échéance. Pli n\'enregistre pas le courrier : '
                                'seule l\'échéance que tu valides est gardée.',
                      style: Textes.corps.copyWith(color: Couleurs.encreDouce),
                    ),
                    if (_erreur != null) ...[const SizedBox(height: Espaces.m), _Alerte(texte: _erreur!)],
                    const SizedBox(height: Espaces.l),
                    FeuillePliee(
                      volets: [
                        if (!kIsWeb)
                          _Choix(
                            icone: Icons.photo_camera_outlined,
                            titre: 'Prendre une photo',
                            detail: 'Le courrier à plat, bien éclairé',
                            onTap: _photographier,
                          ),
                        _Choix(
                          icone: Icons.upload_file_outlined,
                          titre: 'Importer un PDF ou une image',
                          detail: '5 Mo maximum',
                          onTap: _importer,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Choix(
                              icone: Icons.content_paste_outlined,
                              titre: 'Coller le texte',
                              detail: 'Depuis un mail ou un espace en ligne',
                              onTap: () => setState(() => _texteOuvert = !_texteOuvert),
                            ),
                            if (_texteOuvert)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(Espaces.m, 0, Espaces.m, Espaces.m),
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
                    const SizedBox(height: Espaces.xl),
                    const Text('Pas de courrier sous la main ?', style: Textes.volet),
                    const SizedBox(height: Espaces.s),
                    for (final exemple in exemples)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mail_outline, color: Couleurs.tampon),
                        title: Text(exemple.titre, style: Textes.corps),
                        subtitle: const Text('Courrier fictif', style: Textes.discret),
                        onTap: () => _lire(CourrierTexte(exemple.texte)),
                      ),
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

class _Choix extends StatelessWidget {
  const _Choix({required this.icone, required this.titre, required this.detail, required this.onTap});

  final IconData icone;
  final String titre;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Espaces.m),
        child: Row(
          children: [
            Icon(icone, color: Couleurs.tampon, size: 28),
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
        decoration: const BoxDecoration(
          color: Couleurs.feuille,
          border: Border(left: BorderSide(color: Couleurs.cire, width: 4)),
        ),
        child: Text(texte, style: Textes.corps),
      ),
    );
  }
}
