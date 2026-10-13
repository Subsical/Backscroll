import 'package:flutter/material.dart';

import '../widgets/common.dart';

const _faint = Color(0x14F3F3F4);
const _strong = Color(0x29F3F3F4);

const _shapes = <(double, List<List<double>>, bool)>[
  (
    88,
    [
      [56, 34, 92, 48],
      [72, 40],
    ],
    false,
  ),
  (
    124,
    [
      [40, 96, 58],
    ],
    true,
  ),
  (
    72,
    [
      [84, 52, 36, 68, 44],
      [60, 88, 32],
      [48, 70],
    ],
    false,
  ),
  (
    104,
    [
      [66, 42, 80],
    ],
    false,
  ),
  (
    64,
    [
      [38, 74, 50, 90],
      [82, 46],
    ],
    true,
  ),
  (
    112,
    [
      [58, 36, 64, 44, 72],
    ],
    false,
  ),
  (
    80,
    [
      [90, 54],
      [42, 68, 36, 78],
      [56],
    ],
    false,
  ),
  (
    96,
    [
      [48, 86, 40, 62],
    ],
    false,
  ),
];

class MessageSkeleton extends StatelessWidget {
  const MessageSkeleton({super.key, this.groups});

  final int? groups;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    Widget group(int index) =>
        _Group(_shapes[index % _shapes.length], compact: compact);
    final count = groups;
    return Semantics(
      label: 'Loading messages',
      child: ExcludeSemantics(
        child: count == null
            ? ListView.builder(
                reverse: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: 24,
                itemBuilder: (context, index) => group(index),
              )
            : Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [for (var i = count - 1; i >= 0; i--) group(i)],
                ),
              ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.shape, {required this.compact});

  final (double, List<List<double>>, bool) shape;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (name, lines, attachment) = shape;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 17, compact ? 12 : 48, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              color: _faint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line([name], color: _strong),
                for (final line in lines) _Line(line),
                if (attachment)
                  Container(
                    width: 240,
                    height: 120,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: _faint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.widths, {this.color = _faint});

  final List<double> widths;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: Wrap(
      spacing: 4,
      runSpacing: 8,
      clipBehavior: Clip.hardEdge,
      children: [
        for (final width in widths)
          Container(
            width: width,
            height: 16,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      ],
    ),
  );
}
