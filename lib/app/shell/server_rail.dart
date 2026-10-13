import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/discord/models.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';

class RailItem extends StatefulWidget {
  const RailItem({
    super.key,
    required this.tooltip,
    required this.child,
    this.selected = false,
    this.onTap,
    this.image = false,
    this.badge,
    this.size = 40,
  });

  final String tooltip;
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final bool image;
  final String? badge;
  final double size;

  @override
  State<RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    final pill = widget.selected ? widget.size : (_hover ? 20.0 : 0.0);
    return SizedBox(
      width: double.infinity,
      height: widget.size + 8,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            top: 0,
            height: widget.size,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 4,
                height: pill,
                decoration: const BoxDecoration(
                  color: Palette.header,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: widget.tooltip,
            decoration: const ShapeDecoration(
              color: Palette.floating,
              shape: _PointingLeft(),
              shadows: Styles.lift,
            ),
            positionDelegate: (tip) => Offset(
              tip.target.dx + tip.targetSize.width / 2 + 14,
              (tip.target.dy - tip.tooltipSize.height / 2).clamp(
                2.0,
                max(2.0, tip.overlaySize.height - tip.tooltipSize.height - 2),
              ),
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: widget.size,
                  height: widget.size,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: active && !widget.image
                        ? Palette.blurple
                        : Palette.hover,
                    borderRadius: BorderRadius.circular(widget.size * 0.28),
                  ),
                  alignment: Alignment.center,
                  child: IconTheme(
                    data: IconThemeData(
                      color: active ? Colors.white : Palette.text,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
          if (widget.badge != null)
            Positioned(
              right: 12,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.danger,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Palette.rail,
                    width: 3,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                child: Text(
                  widget.badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PointingLeft extends ShapeBorder {
  const _PointingLeft();

  static const _arrow = 5.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path.combine(
    PathOperation.union,
    Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8))),
    Path()
      ..moveTo(rect.left + 1, rect.center.dy - _arrow)
      ..lineTo(rect.left - _arrow, rect.center.dy)
      ..lineTo(rect.left + 1, rect.center.dy + _arrow)
      ..close(),
  );

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      canvas.drawPath(
        getOuterPath(rect, textDirection: textDirection),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Palette.divider,
      );

  @override
  ShapeBorder scale(double t) => this;
}

class GuildIcon extends StatelessWidget {
  const GuildIcon({super.key, required this.guild, this.size = 40});

  final Guild guild;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = guild.iconUrl();
    if (url == null) {
      return Text(
        initials(guild.name),
        style: TextStyle(
          color: Palette.header,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Image(
      image: AppScope.of(context).images(url),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Text(initials(guild.name)),
    );
  }
}

class RailSeparator extends StatelessWidget {
  const RailSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 1,
    margin: const EdgeInsets.only(bottom: 8),
    color: Palette.divider,
  );
}

class ServerRail extends StatelessWidget {
  const ServerRail({
    super.key,
    required this.homeSelected,
    required this.onHome,
    required this.onGuild,
    required this.onAddAccount,
    this.width = 72,
    this.room = 0,
  });

  final bool homeSelected;
  final VoidCallback onHome;
  final ValueChanged<String> onGuild;
  final VoidCallback onAddAccount;
  final double width;
  final double room;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final library = services.library;
    return Container(
      width: width,
      color: Palette.rail,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          library,
          services.session,
          services.exports,
        ]),
        builder: (context, _) {
          final running = services.exports.queue.remaining;
          final bot = services.session.isBot;
          return Column(
            children: [
              const SizedBox(height: 1),
              RailItem(
                tooltip: bot ? 'Exports' : 'Direct Messages',
                selected: homeSelected,
                onTap: onHome,
                badge: running > 0 ? '$running' : null,
                child: const BackscrollGlyph(size: 26),
              ),
              const RailSeparator(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final g in library.guilds)
                      RailItem(
                        tooltip: g.guild.name,
                        image: g.guild.icon != null,
                        selected:
                            !homeSelected &&
                            library.selectedGuildId == g.guild.id,
                        onTap: () => onGuild(g.guild.id),
                        child: GuildIcon(guild: g.guild),
                      ),
                    if (library.guilds.isNotEmpty)
                      const Center(child: RailSeparator()),
                    RailItem(
                      tooltip: 'Add an account',
                      onTap: onAddAccount,
                      child: const Icon(Icons.add_rounded, size: 24),
                    ),
                  ],
                ),
              ),
              SizedBox(height: room),
            ],
          );
        },
      ),
    );
  }
}
