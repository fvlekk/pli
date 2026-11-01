import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../theme.dart';

/// A rounded pill, like Buddy's « Astuce » / « 🚗 transports » tags.
/// Filled when `fond` is set, outlined otherwise.
class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.couleur = Couleurs.encre, this.fond});

  final String texte;
  final Color couleur;
  final Color? fond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fond ?? Couleurs.carte,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fond ?? Couleurs.bord, width: 1.5),
      ),
      child: Text(
        texte,
        style: Textes.etiquette.copyWith(color: couleur),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The countdown pill: coral when it is urgent (a week or less), mint otherwise, grey when done.
class PastilleRebours extends StatelessWidget {
  const PastilleRebours({super.key, required this.jours, this.fait = false});

  final int? jours;
  final bool fait;

  @override
  Widget build(BuildContext context) {
    if (fait) return const Pastille('Fait', couleur: Couleurs.fait, fond: Couleurs.mentheFond);
    final j = jours;
    if (j == null) return const Pastille('Date à choisir', couleur: Couleurs.rouge, fond: Couleurs.corailPale);
    return estUrgent(j)
        ? Pastille(rebours(j), couleur: Couleurs.rouge, fond: Couleurs.corailPale)
        : Pastille(rebours(j), couleur: Couleurs.menthe, fond: Couleurs.mentheFond);
  }
}

/// One deadline as a Buddy-style card. `enAvant` turns it into the lilac card for what to do first.
class CarteEcheance extends StatelessWidget {
  const CarteEcheance({
    super.key,
    required this.echeance,
    required this.aujourdhui,
    required this.onTap,
    this.enAvant = false,
  });

  final Echeance echeance;
  final DateTime aujourdhui;
  final VoidCallback onTap;
  final bool enAvant;

  @override
  Widget build(BuildContext context) {
    final e = echeance;
    final jours = joursRestants(e.dateLimite, aujourdhui);
    final details = [if (e.montant != null) euros(e.montant!), if (e.aVerifier && !e.fait) 'À vérifier'].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: Espaces.m),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Rayons.carte),
          child: Ink(
            decoration: enAvant ? decorationCarte(fond: Couleurs.lilas, bord: Couleurs.lilasBord) : decorationCarte(),
            padding: const EdgeInsets.all(Espaces.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (enAvant) ...[
                  const Text('À FAIRE EN PREMIER', style: Textes.surtitre),
                  const SizedBox(height: Espaces.s),
                ],
                Row(
                  children: [
                    // Both pills may shrink (ellipsis) so a large text size never overflows; the countdown first.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            flex: 3,
                            child: PastilleRebours(jours: jours, fait: e.fait),
                          ),
                          const SizedBox(width: Espaces.s),
                          Flexible(
                            flex: 2,
                            child: Pastille('${emojiOrganisme(e.organisme)} ${libelleOrganisme(e.organisme)}'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Espaces.s),
                    const Icon(Icons.calendar_today_outlined, size: 15, color: Couleurs.rouge),
                    const SizedBox(width: Espaces.xs),
                    Text(dateChiffres(e.dateLimite), style: Textes.etiquette.copyWith(color: Couleurs.rouge)),
                  ],
                ),
                const SizedBox(height: Espaces.s + 2),
                Text(
                  e.titre,
                  style: Textes.ligne.copyWith(
                    decoration: e.fait ? TextDecoration.lineThrough : null,
                    color: e.fait ? Couleurs.encreDouce : Couleurs.encre,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty) ...[const SizedBox(height: 2), Text(details, style: Textes.discret)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
