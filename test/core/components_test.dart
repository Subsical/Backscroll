import 'package:backscroll/core/discord/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_discord.dart';

void main() {
  test('reads the layout of a component message', () {
    final message = Message.fromJson(
      componentMessage(channelId: '100000000000000001'),
    );
    expect(message.content, isEmpty);
    expect(message.components, hasLength(2));

    final container = message.components.first as ContainerComponent;
    expect(container.accentColor, 0xE67E22);
    expect(container.spoiler, isFalse);
    expect(container.components.map((c) => c.runtimeType), [
      SectionComponent,
      SeparatorComponent,
      GalleryComponent,
      TextComponent,
      FileComponent,
      RowComponent,
      RowComponent,
    ]);

    final section = container.components[0] as SectionComponent;
    expect(section.components.cast<TextComponent>().map((t) => t.content), [
      '## Clip ready',
      'Converted for <@200000000000000001> in **4 s**',
    ]);
    final thumbnail = section.accessory as ThumbnailComponent;
    expect(thumbnail.media.bestUrl, componentThumbUrl);
    expect(thumbnail.media.description, 'Cover art');

    final separator = container.components[1] as SeparatorComponent;
    expect(separator.divider, isTrue);
    expect(separator.large, isTrue);

    final gif = (container.components[2] as GalleryComponent).items.single;
    expect(gif.bestUrl, componentGifUrl);
    expect((gif.width, gif.height), (320, 568));
    expect(gif.isVideo, isFalse);

    final file = container.components[4] as FileComponent;
    expect(file.media.bestUrl, componentZipUrl);
    expect((file.name, file.size), ('build.zip', 2048));

    final buttons = (container.components[5] as RowComponent).components
        .cast<ButtonComponent>();
    expect(buttons.map((b) => (b.kind, b.label, b.url, b.disabled)), [
      (ButtonKind.link, 'Open original', 'https://example.com/original', false),
      (ButtonKind.danger, 'Delete', null, true),
    ]);
    expect(buttons.last.emoji?.name, '\u{1F5D1}');

    final select =
        (container.components[6] as RowComponent).components.single
            as SelectComponent;
    expect(select.text, 'Double');

    expect(
      (message.components.last as TextComponent).content,
      'Expires in a day',
    );
  });

  test('walks every component, nested ones included', () {
    final message = Message.fromJson(
      componentMessage(channelId: '100000000000000001'),
    );
    final seen = <Type, int>{};
    visitComponents(
      message.components,
      (c) => seen[c.runtimeType] = (seen[c.runtimeType] ?? 0) + 1,
    );
    expect(seen, {
      ContainerComponent: 1,
      SectionComponent: 1,
      TextComponent: 4,
      ThumbnailComponent: 1,
      SeparatorComponent: 1,
      GalleryComponent: 1,
      FileComponent: 1,
      RowComponent: 2,
      ButtonComponent: 2,
      SelectComponent: 1,
    });
  });

  test('messages without components have none', () {
    final message = Message.fromJson(
      generateMessages(1, channelId: '100000000000000001').single,
    );
    expect(message.components, isEmpty);
  });

  test('odd component data is skipped instead of breaking the message', () {
    final message = Message.fromJson({
      ...generateMessages(1, channelId: '100000000000000001').single,
      'components': [
        'nonsense',
        {'type': 11},
        {'type': 13, 'file': {}},
        {
          'type': 12,
          'items': [
            {'media': null},
            {
              'media': {'url': 'https://example.com/a.mp4'},
            },
          ],
        },
        {
          'type': 1,
          'components': [
            {'type': 2, 'style': 6, 'sku_id': '1'},
            {'type': 2, 'style': 0, 'label': 'Plain'},
            {'type': 5, 'custom_id': 'who'},
          ],
        },
        {'type': 14},
        {
          'type': 1,
          'components': [
            {'type': 2, 'style': 6, 'sku_id': '2'},
          ],
        },
      ],
    });
    expect(message.components.map((c) => c.runtimeType), [
      GalleryComponent,
      RowComponent,
      SeparatorComponent,
    ]);
    final video = (message.components[0] as GalleryComponent).items.single;
    expect(video.isVideo, isTrue);
    expect(video.bestUrl, 'https://example.com/a.mp4');
    final row = (message.components[1] as RowComponent).components;
    expect((row[0] as ButtonComponent).kind, ButtonKind.secondary);
    expect((row[1] as SelectComponent).text, 'Make a selection');
    final separator = message.components[2] as SeparatorComponent;
    expect((separator.divider, separator.large), (true, false));
  });
}
