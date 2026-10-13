import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/discord/models.dart';
import '../scope.dart';
import '../theme.dart';

enum ButtonTone { primary, secondary, danger, success, link }

class DiscordButton extends StatelessWidget {
  const DiscordButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = ButtonTone.primary,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.dense = false,
    this.radius = 8,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonTone tone;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool dense;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      ButtonTone.primary => (Palette.blurple, Colors.white),
      ButtonTone.secondary => (Palette.hover, Colors.white),
      ButtonTone.danger => (Palette.danger, Colors.white),
      ButtonTone.success => (Palette.green, Colors.white),
      ButtonTone.link => (Colors.transparent, Palette.text),
    };
    final enabled = onPressed != null && !busy;
    final child = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledForegroundColor: foreground,
          overlayColor: tone == ButtonTone.link ? Palette.muted : Colors.black,
          minimumSize: Size(dense ? 60 : 96, dense ? 32 : 40),
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: const TextStyle(
            fontFamily: Fonts.family,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(text, style: Styles.label),
  );
}

class HoverTile extends StatefulWidget {
  const HoverTile({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.margin = const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    this.radius = 8,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;

  @override
  State<HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<HoverTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: widget.margin,
    child: MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? Palette.selected
                : _hover
                ? Palette.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

class Clickable extends StatelessWidget {
  const Clickable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    ),
  );
}

class PanelHint extends StatelessWidget {
  const PanelHint({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Palette.faint),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: Styles.small),
          if (busy) ...[
            const SizedBox(height: 16),
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            DiscordButton(
              label: action!,
              tone: ButtonTone.secondary,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    ),
  );
}

class CircleImage extends StatelessWidget {
  const CircleImage({
    super.key,
    required this.url,
    this.size = 40,
    this.fallback,
  });

  final String? url;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final images = AppScope.of(context).images;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Palette.blurple,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: fallback,
    );
    if (url == null) return placeholder;
    return ClipOval(
      child: Image(
        image: images(url!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 40, this.url});

  final DiscordUser user;
  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) => CircleImage(
    url: url ?? user.avatarUrl(size: size > 64 ? 256 : 128),
    size: size,
  );
}

String initials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(3).map((w) => w.characters.first).join();
}

class ChannelGlyph extends StatelessWidget {
  const ChannelGlyph(
    this.channel, {
    super.key,
    this.size = 20,
    this.color = Palette.channel,
  });

  final Channel channel;
  final double size;
  final Color color;

  static IconData iconFor(Channel channel) => switch (channel.type) {
    ChannelType.guildVoice => Icons.volume_up_rounded,
    ChannelType.guildStageVoice => Icons.podcasts_rounded,
    ChannelType.guildAnnouncement => Icons.campaign_rounded,
    ChannelType.guildForum => Icons.forum_rounded,
    ChannelType.guildMedia => Icons.perm_media_rounded,
    ChannelType.announcementThread ||
    ChannelType.publicThread ||
    ChannelType.privateThread => Icons.chat_bubble_outline_rounded,
    ChannelType.dm || ChannelType.groupDm => Icons.alternate_email_rounded,
    _ => Icons.tag_rounded,
  };

  @override
  Widget build(BuildContext context) =>
      Icon(iconFor(channel), size: size, color: color);
}

class GroupIcon extends StatelessWidget {
  const GroupIcon({super.key, required this.channel, this.size = 32});

  final Channel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = channel.iconUrl();
    if (url != null && !channel.isDm) return CircleImage(url: url, size: size);
    if (channel.isDm && channel.recipients.isNotEmpty) {
      return UserAvatar(user: channel.recipients.first, size: size);
    }
    const colors = [
      Color(0xFF3BA55C),
      Color(0xFFED4245),
      Color(0xFFFAA61A),
      Color(0xFF5865F2),
      Color(0xFFEB459E),
    ];
    final color =
        colors[int.parse(channel.id.substring(channel.id.length - 3)) %
            colors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.group_rounded, color: Colors.white, size: size * 0.55),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Palette.blurple});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    height: 15,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Align(
      widthFactor: 1,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    ),
  );
}

class ThinProgress extends StatelessWidget {
  const ThinProgress({
    super.key,
    required this.value,
    this.color = Palette.blurple,
    this.height = 6,
  });

  final double? value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      value: value,
      minHeight: height,
      color: color,
      backgroundColor: Palette.selected,
    ),
  );
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 720;

bool get isMobileOS => defaultTargetPlatform == TargetPlatform.android;
