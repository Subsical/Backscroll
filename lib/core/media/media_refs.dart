import '../discord/cdn.dart';
import '../discord/models.dart';
import '../export/context.dart';
import '../markdown/ast.dart';
import '../markdown/emoji.dart';
import '../markdown/parser.dart';

class MediaRef {
  const MediaRef(this.url, {this.attachment});

  final String url;
  final Attachment? attachment;

  bool get expiring => attachment != null || isDiscordAttachmentUrl(url);
}

String emojiImageUrl(PartialEmoji emoji) => emoji.isCustom
    ? customEmojiUrl(emoji.id!, animated: emoji.animated)
    : twemojiUrl(emoji.name);

// keep in sync with what the writers pass to ExportContext.media
List<MediaRef> collectMediaRefs(
  List<Message> messages,
  ExportContext ctx, {
  required bool full,
}) {
  final refs = <String, MediaRef>{};

  void add(String? url, {Attachment? attachment}) {
    if (url == null || url.isEmpty) return;
    refs.putIfAbsent(url, () => MediaRef(url, attachment: attachment));
  }

  void emojiIn(String? text) {
    if (!full || text == null || text.isEmpty) return;
    visitNodes(parseMarkdown(text), (node) {
      if (node is CustomEmojiNode) {
        add(customEmojiUrl(node.id, animated: node.animated));
      } else if (node is EmojiNode) {
        add(twemojiUrl(node.emoji));
      }
    });
  }

  void user(DiscordUser user) {
    if (full) add(ctx.avatarUrl(user));
  }

  void layout(List<Component> components) {
    visitComponents(components, (component) {
      switch (component) {
        case TextComponent(content: final text):
          emojiIn(text);
        case ThumbnailComponent(:final media) || FileComponent(:final media):
          add(media.bestUrl);
        case GalleryComponent(:final items):
          for (final item in items) {
            add(item.bestUrl);
          }
        case ButtonComponent(:final emoji?) when full:
          add(emojiImageUrl(emoji));
        default:
          break;
      }
    });
  }

  void embed(Embed e) {
    add(e.thumbnail?.bestUrl);
    add(e.video?.bestUrl);
    for (final image in e.images) {
      add(image.bestUrl);
    }
    layout(e.components);
    if (!full) return;
    add(e.author?.iconUrl);
    add(e.footer?.iconUrl);
    emojiIn(e.title);
    emojiIn(e.description);
    for (final field in e.fields) {
      emojiIn(field.name);
      emojiIn(field.value);
    }
  }

  void content(Message m) {
    for (final a in m.attachments) {
      add(a.url, attachment: a);
    }
    mergeGalleryEmbeds(m.embeds).forEach(embed);
    for (final s in m.stickers) {
      add(s.url);
    }
    layout(m.components);
    emojiIn(m.content);
    if (full) {
      for (final r in m.reactions) {
        add(emojiImageUrl(r.emoji));
      }
      for (final answer in m.poll?.answers ?? const <PollAnswer>[]) {
        if (answer.emoji != null) add(emojiImageUrl(answer.emoji!));
      }
      m.mentions.forEach(user);
    }
    for (final f in m.forwards) {
      for (final a in f.attachments) {
        add(a.url, attachment: a);
      }
      mergeGalleryEmbeds(f.embeds).forEach(embed);
      for (final s in f.stickers) {
        add(s.url);
      }
      layout(f.components);
      emojiIn(f.content);
    }
  }

  for (final m in messages) {
    user(m.author);
    content(m);
    if (m.interaction != null) user(m.interaction!.user);
    final ref = m.referenced;
    if (ref == null) continue;
    user(ref.author);
    if (m.type == MessageType.threadStarter) {
      content(ref);
    } else {
      emojiIn(ref.content);
    }
  }
  return refs.values.toList();
}
