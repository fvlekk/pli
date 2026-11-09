import 'package:flutter/material.dart';

import '../theme.dart';

/// Where the user writes to use their rights. Keep in step with the notice below.
const contactConfidentialite = 'fvlekk@gmail.com';

/// The privacy notice (GDPR art. 13): who is responsible, what leaves the phone and to whom, what is kept and how
/// long, the user's rights. Change it whenever what Pli sends or keeps changes.
class EcranConfidentialite extends StatelessWidget {
  const EcranConfidentialite({super.key});

  static const _sections = [
    (
      'Qui s\'en occupe',
      'Pli est un prototype développé à titre personnel par Falek. Pour toute question ou demande : '
          '$contactConfidentialite.',
    ),
    (
      'Ce qui part de ton téléphone',
      'Quand tu ajoutes un courrier, son texte, sa photo ou son PDF part au serveur de Pli, puis à Claude, l\'IA '
          'd\'Anthropic (États-Unis), qui le lit. Le serveur de Pli ne garde pas le courrier et n\'en écrit rien dans '
          'ses journaux. Ton adresse IP sert seulement à limiter les abus : gardée en mémoire au plus un jour, '
          'jamais écrite dans ces journaux.',
    ),
    (
      'Chez Anthropic',
      'Anthropic ne se sert pas de ton courrier pour entraîner ses modèles et l\'efface sous 30 jours, sauf '
          'obligation légale ou abus.',
    ),
    (
      'Ce que Pli garde',
      'Les échéances que tu enregistres (organisme, action, date, montant, résumé) et ton compte : sans adresse '
          'si tu restes sans compte Google, ton adresse Google si tu te connectes. Les deux sont chez Google '
          'Firebase ; les échéances sont stockées en Europe (Paris).',
    ),
    ('Pourquoi', 'Seulement pour lire tes courriers et te montrer tes échéances. Pas de publicité, rien n\'est vendu.'),
    (
      'Combien de temps',
      'Tant que tu ne les supprimes pas. « Supprimer mes données », dans ton compte, efface tes échéances et, si tu '
          'es connecté avec Google, ton compte Pli. Sans compte Google, un identifiant anonyme et vide peut rester. Si tu as rejoint un compte Google qui avait déjà une liste, l\'ancienne liste de cet appareil '
          'reste sur le serveur sans être visible : écris-nous pour l\'effacer.',
    ),
    (
      'Tes droits',
      'Tu peux demander à voir, corriger ou effacer tes données, et t\'opposer à leur usage, en écrivant à '
          '$contactConfidentialite. Tu peux aussi te plaindre auprès de la CNIL (cnil.fr).',
    ),
    (
      'Qui d\'autre intervient',
      'Anthropic (lecture des courriers), Google Firebase (comptes et échéances), Google reCAPTCHA (vérifie, sur '
          'le web, que les demandes viennent de l\'appli), Render (serveur de lecture) et '
          'Vercel (site de l\'appli), qui notent les connexions, adresse IP comprise, dans leurs journaux techniques.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espaces.l, Espaces.s, Espaces.l, Espaces.xl),
          children: [
            for (final (titre, texte) in _sections) ...[
              Text(titre, style: Textes.section),
              const SizedBox(height: Espaces.xs),
              Text(texte, style: Textes.corps),
              const SizedBox(height: Espaces.l),
            ],
            const Text('Mis à jour le 8 novembre 2026.', style: Textes.discret),
          ],
        ),
      ),
    );
  }
}
