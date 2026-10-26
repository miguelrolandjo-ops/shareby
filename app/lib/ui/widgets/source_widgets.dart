import 'package:flutter/material.dart';

import '../../data/sources.dart';

/// A source's coloured badge ("IG", "SHP"), for lists and chips.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.info, this.size = 28});

  final SourceInfo info;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: info.color, borderRadius: BorderRadius.circular(size * 0.28)),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(info.label,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
        ),
      ),
    );
  }
}
