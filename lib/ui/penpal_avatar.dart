import 'package:flutter/material.dart';

import '../core/penpal_card.dart';
import '../services/penpal_card_store.dart';

class PenpalAvatar extends StatelessWidget {
  const PenpalAvatar({
    super.key,
    required this.store,
    this.card,
    this.radius = 22,
  });
  final PenpalCardStore store;
  final PenpalCard? card;
  final double radius;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final file = card == null
          ? store.activeAvatarFile
          : store.avatarFile(card!);
      return CircleAvatar(
        radius: radius,
        foregroundImage: file == null ? null : FileImage(file),
        onForegroundImageError: file == null ? null : (_, _) {},
        child: const Icon(Icons.person_outline),
      );
    },
  );
}
