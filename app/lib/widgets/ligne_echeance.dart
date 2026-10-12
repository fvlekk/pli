import 'package:flutter/material.dart';

import '../modeles/echeance.dart';
import '../modeles/libelles.dart';
import '../outils/dates.dart';
import '../theme.dart';
import 'cachet.dart';

class LigneEcheance extends StatelessWidget {
  const LigneEcheance({super.key, required this.echeance, required this.aujourdhui, required this.onTap});

  final Echeance echeance;
  final DateTime aujourdhui;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final jours = joursRestants(echeance.dateLimite, aujourdhui);
    final rebours = compteARebours(jours);
    final couleur = echeance.fait ? Couleurs.pli : (estUrgent(jours) ? Couleurs.cire : Couleurs.tampon);
    final quand = jours < 0
        ? 'était à faire le ${dateCourte(echeance.dateLimite)}'
        : 'avant le ${dateCourte(echeance.dateLimite)}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espaces.m, vertical: Espaces.s + 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Cachet(
              nombre: echeance.fait ? '✓' : rebours.nombre,
              unite: echeance.fait ? 'fait' : rebours.unite,
              couleur: echeance.fait ? Couleurs.fait : couleur,
              inclinaison: Cachet.inclinaisonPour(echeance.id),
              semantique: echeance.fait ? 'Fait' : '${rebours.nombre} ${rebours.unite}',
            ),
            const SizedBox(width: Espaces.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    echeance.titre,
                    style: Textes.ligne.copyWith(
                      decoration: echeance.fait ? TextDecoration.lineThrough : null,
                      color: echeance.fait ? Couleurs.encreDouce : Couleurs.encre,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text('${libelleOrganisme(echeance.organisme)}, $quand', style: Textes.discret),
                  if (echeance.aVerifier && !echeance.fait)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'À vérifier',
                        style: Textes.discret.copyWith(color: Couleurs.cire, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            if (echeance.montant != null) ...[
              const SizedBox(width: Espaces.s),
              Text(euros(echeance.montant!), style: Textes.montant),
            ],
          ],
        ),
      ),
    );
  }
}
