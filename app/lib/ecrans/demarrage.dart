import 'package:flutter/material.dart';

import '../theme.dart';

/// Shown instead of a blank page when Firebase or the anonymous session cannot start (offline, an ad blocker
/// that stops Firebase).
class EcranDemarrageImpossible extends StatefulWidget {
  const EcranDemarrageImpossible({super.key, required this.onReessayer});

  /// Tries the whole start again; on success the real app replaces this screen.
  final Future<void> Function() onReessayer;

  @override
  State<EcranDemarrageImpossible> createState() => _EcranDemarrageImpossibleState();
}

class _EcranDemarrageImpossibleState extends State<EcranDemarrageImpossible> {
  bool _enCours = false;

  Future<void> _reessayer() async {
    setState(() => _enCours = true);
    await widget.onReessayer();
    if (mounted) setState(() => _enCours = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pli',
      debugShowCheckedModeBanner: false,
      theme: themePli(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Espaces.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('pli', style: Textes.marque),
                const Spacer(),
                const Text('Pli n\'arrive pas à démarrer', style: Textes.titre),
                const SizedBox(height: Espaces.s),
                const Text(
                  'Vérifie ta connexion. Si un bloqueur de publicité est actif, autorise ce site, puis réessaie.',
                  style: Textes.corps,
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _enCours ? null : _reessayer,
                  child: Text(_enCours ? 'Connexion…' : 'Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
