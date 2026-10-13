import '../../discord/models.dart';

class Strong {
  const Strong(this.text);
  final String text;
}

class MessageLink {
  const MessageLink(this.messageId, this.label);
  final String? messageId;
  final String label;
}

class ThreadLink {
  const ThreadLink(this.thread);
  final Channel thread;
}

class SystemLine {
  const SystemLine(this.icon, this.tone, this.parts);

  final String icon;
  final String tone;
  final List<Object> parts;
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String callDuration(Duration d) {
  if (d.inHours >= 1) return _plural(d.inHours, 'hour');
  if (d.inMinutes >= 1) return _plural(d.inMinutes, 'minute');
  return 'a few seconds';
}

SystemLine? systemLine(Message m, {String? guildName}) {
  final author = m.author;
  final other = m.mentions.isEmpty ? null : m.mentions.first;
  switch (m.type) {
    case MessageType.recipientAdd:
      return SystemLine('join', 'join', [
        author,
        ' added ',
        other ?? 'someone',
        ' to the group.',
      ]);
    case MessageType.recipientRemove:
      if (other == null || other.id == author.id) {
        return SystemLine('leave', 'leave', [author, ' left the group.']);
      }
      return SystemLine('leave', 'leave', [
        author,
        ' removed ',
        other,
        ' from the group.',
      ]);
    case MessageType.call:
      final ended = m.callEndedAt;
      return SystemLine('phone', 'join', [
        author,
        ended == null
            ? ' started a call.'
            : ' started a call that lasted '
                  '${callDuration(ended.difference(m.timestamp))}.',
      ]);
    case MessageType.channelNameChange:
      return SystemLine('pencil', '', [
        author,
        ' changed the channel name: ',
        Strong(m.content),
      ]);
    case MessageType.channelIconChange:
      return SystemLine('pencil', '', [author, ' changed the channel icon.']);
    case MessageType.pinnedMessage:
      return SystemLine('pin', 'pin', [
        author,
        ' pinned ',
        MessageLink(m.reference?.messageId, 'a message'),
        ' to this channel.',
      ]);
    case MessageType.userJoin:
      return SystemLine('join', 'join', [author, ' joined the server.']);
    case MessageType.boost:
      final count = int.tryParse(m.content) ?? 1;
      return SystemLine('boost', 'boost', [
        author,
        count > 1
            ? ' just boosted the server $count times!'
            : ' just boosted the server!',
      ]);
    case MessageType.boostTier1 ||
        MessageType.boostTier2 ||
        MessageType.boostTier3:
      final level = m.type - MessageType.boostTier1 + 1;
      return SystemLine('boost', 'boost', [
        author,
        ' just boosted the server! ',
        Strong(guildName ?? 'The server'),
        ' has achieved ',
        Strong('Level $level!'),
      ]);
    case MessageType.followAdd:
      return SystemLine('join', 'join', [
        author,
        ' has added ',
        Strong(m.content),
        ' to this channel. Its most important updates will show up here.',
      ]);
    case MessageType.threadCreated:
      final threadId = m.reference?.channelId;
      return SystemLine('thread', 'thread', [
        author,
        ' started a thread: ',
        if (threadId != null)
          ThreadLink(
            Channel(
              id: threadId,
              type: ChannelType.publicThread,
              name: m.content,
            ),
          )
        else
          Strong(m.content),
        '.',
      ]);
    case MessageType.stageStart:
      return SystemLine('stage', '', [author, ' started ', Strong(m.content)]);
    case MessageType.stageEnd:
      return SystemLine('stage', '', [author, ' ended ', Strong(m.content)]);
    case MessageType.stageSpeaker:
      return SystemLine('stage', '', [author, ' is now a speaker.']);
    case MessageType.stageTopic:
      return SystemLine('stage', '', [
        author,
        ' changed the Stage topic: ',
        Strong(m.content),
      ]);
    case MessageType.pollResult:
      String? field(String name) {
        for (final e in m.embeds) {
          for (final f in e.fields) {
            if (f.name == name) return f.value;
          }
        }
        return null;
      }
      final question = field('poll_question_text') ?? 'a poll';
      final winner = field('victor_answer_text');
      final votes = int.tryParse(field('victor_answer_votes') ?? '') ?? 0;
      final total = int.tryParse(field('total_votes') ?? '') ?? 0;
      return SystemLine('poll', '', [
        author,
        "'s poll ",
        Strong(question),
        ' has closed.',
        if (winner != null) ...[
          ' Winner: ',
          Strong(winner),
          ' (${_plural(votes, 'vote')} of $total).',
        ],
      ]);
  }
  return null;
}
