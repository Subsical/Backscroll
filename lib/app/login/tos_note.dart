import 'package:flutter/material.dart';

import '../theme.dart';

class TosNote extends StatelessWidget {
  const TosNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0x1AF0B232),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x66F0B232)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, color: Palette.yellow, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Automating a user account with its token is against Discord\'s Terms '
            'of Service. Use it at your own risk.',
            style: TextStyle(color: Palette.text, fontSize: 14, height: 1.35),
          ),
        ),
      ],
    ),
  );
}
