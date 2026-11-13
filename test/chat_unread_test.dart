import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/chat/chat_unread.dart';
import 'package:jobmate/features/chat/chat_read_events.dart';

import 'fixtures/chat_ui.dart';

void main() {
  late ChatFixtureSource source;
  late ChatFixtureFeed feed;
  late ChatUnreadController unread;
  setUp(() {
    source = ChatFixtureSource();
    feed = ChatFixtureFeed();
    unread = ChatUnreadController(source, realtime: feed);
  });
  tearDown(() async {
    unread.dispose();
    await source.accounts.close();
  });
  test(
    'navigation unread checks all pages, using server incoming-only counts',
    () async {
      source.inbox = [
        for (var i = 1; i <= 101; i++)
          {...conversationRow(id: i), 'unread_count': i == 1 ? 1 : 0},
      ];
      await unread.refresh();
      expect(source.reads, 2);
      expect(unread.hasUnread, true);
      expect(source.marks, 0);
      source.inbox = [
        for (final row in source.inbox) {...row, 'unread_count': 0},
      ];
      await unread.refresh();
      expect(unread.hasUnread, false);
    },
  );
  test('Realtime and local read invalidations repair and clear the dot without writes', () async {
    source.inbox = [
      {...conversationRow(), 'unread_count': 0},
    ];
    await unread.start();
    expect(unread.hasUnread, false);
    source.inbox = [conversationRow()];
    feed.callback!();
    await Future<void>.delayed(Duration.zero);
    expect(unread.hasUnread, true);
    source.inbox = [
      {...conversationRow(), 'unread_count': 0},
    ];
    chatReadInvalidations.value++;
    await Future<void>.delayed(Duration.zero);
    expect(unread.hasUnread, false);
    expect(source.marks, 0);
    expect(source.sends, isEmpty);
  });
  test('account change clears immediately and rejects a stale old-account response', () async {
    await unread.refresh();
    expect(unread.hasUnread, true);
    final hold = Completer<Object?>();
    source.hold = hold;
    final loading = unread.refresh();
    source.changeAccount(null);
    expect(unread.hasUnread, false);
    hold.complete([conversationRow()]);
    await loading;
    expect(unread.hasUnread, false);
  });
}
