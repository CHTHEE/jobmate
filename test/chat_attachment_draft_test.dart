import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/chat/chat_attachment_draft.dart';
import 'package:jobmate/features/chat/chat_page.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'fixtures/chat_ui.dart';

void main() {
  final headers = <String, List<int>>{
    'jpg': [255, 216, 255],
    'jpeg': [255, 216, 255],
    'png': [137, 80, 78, 71, 13, 10, 26, 10],
    'pdf': [37, 80, 68, 70, 45],
    'docx': [80, 75, 3, 4],
    'xlsx': [80, 75, 3, 4],
  };
  for (final entry in headers.entries) {
    test(
      '${entry.key} selection uses extension plus basic header (not full content validation)',
      () {
        final bytes = Uint8List.fromList(entry.value);
        final draft = ChatAttachmentDraft.select(
          'QA.${entry.key.toUpperCase()}',
          bytes,
        );
        expect(draft.isImage, ['jpg', 'jpeg', 'png'].contains(entry.key));
        bytes[0] = 0;
        expect(draft.bytes[0], entry.value.first);
        expect(() => draft.bytes[0] = 0, throwsUnsupportedError);
      },
    );
  }
  test(
    'rejects unsupported, renamed executable, path and malformed filenames',
    () {
      for (final name in [
        'a.exe',
        'a.doc',
        'a.xls',
        'a.docm',
        'a.xlsm',
        'a.svg',
        'a.gif',
        'a.zip',
        '../a.pdf',
        'a\\b.pdf',
        'a\n.pdf',
        '',
      ]) {
        expect(
          () => ChatAttachmentDraft.select(
            name,
            Uint8List.fromList(headers['pdf']!),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ChatAttachmentDraft.select(
          'renamed.pdf',
          Uint8List.fromList([77, 90, 0]),
        ),
        throwsFormatException,
      );
      expect(
        () => ChatAttachmentDraft.select('a.pdf', Uint8List(0)),
        throwsFormatException,
      );
    },
  );
  test('5 MB exact boundary accepted locally, one extra byte rejected', () {
    final bytes = Uint8List(ChatAttachmentDraft.maximumBytes)
      ..setAll(0, headers['pdf']!);
    expect(ChatAttachmentDraft.select('a.pdf', bytes).sizeLabel, '5.0 MB');
    expect(
      () => ChatAttachmentDraft.select('a.pdf', Uint8List(bytes.length + 1)),
      throwsFormatException,
    );
  });

  final messageField = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Message',
  );
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets(
      'preview at $width blocks caption-only dispatch, removes safely, incoming-only read action',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = ChatFixtureSource();
        final ui = fixtureChatUi(source: source);
        final key = GlobalKey<ChatPageState>();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => ChatPage(
                key: key,
                controller: ui,
                conversationId: chatConversation,
                pickAttachment: () async => XFile.fromData(
                  Uint8List.fromList(headers['pdf']!),
                  name: 'QA.pdf',
                  path: 'QA.pdf',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        addTearDown(source.accounts.close);
        await tester.pumpWidget(
          MaterialApp.router(theme: JobMateTheme.light(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mark read'), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Send',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(messageField, 'caption');
        await tester.tap(
          find.byTooltip('Preview attachment (upload unavailable)'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('QA.pdf'), findsOneWidget);
        expect(find.text(ChatAttachmentDraft.unavailable), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) =>
                      w is IconButton &&
                      w.tooltip == 'Attachment sending is unavailable',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(messageField);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(source.sends, isEmpty);
        expect(source.marks, 1); // Only the displayed incoming message.
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Remove selected file'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Send',
                ),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(
          find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Send'),
        );
        await tester.pumpAndSettle();
        expect(
          source.sends.single.body,
          'caption',
        ); // fake source, no live write
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'picker cancellation and validation failure preserve the selected draft; file-only exit is guarded',
    (tester) async {
      final source = ChatFixtureSource();
      final ui = fixtureChatUi(source: source);
      final key = GlobalKey<ChatPageState>();
      var picks = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ChatPage(
              key: key,
              controller: ui,
              conversationId: chatConversation,
              pickAttachment: () async {
                picks++;
                if (picks == 2) return null;
                return XFile.fromData(
                  Uint8List.fromList(headers['pdf']!),
                  name: picks == 3 ? 'bad.exe' : 'QA.pdf',
                  path: picks == 3 ? 'bad.exe' : 'QA.pdf',
                );
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(source.accounts.close);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.byTooltip('Preview attachment (upload unavailable)'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('QA.pdf'), findsOneWidget);
      }
      expect(find.textContaining('Choose JPG'), findsOneWidget);
      final exit = key.currentState!.confirmExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(await exit, isFalse);
      expect(ui.draft, isEmpty);
      expect(source.sends, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'attachment-only exit prompts and late picker cannot cross account switch',
    (tester) async {
      final source = ChatFixtureSource();
      final ui = fixtureChatUi(source: source);
      final picked = Completer<XFile?>();
      final key = GlobalKey<ChatPageState>();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ChatPage(
              key: key,
              controller: ui,
              conversationId: chatConversation,
              pickAttachment: () => picked.future,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(source.accounts.close);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Preview attachment (upload unavailable)'),
      );
      await tester.pump();
      final exit = key.currentState!.confirmExit();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Stay'));
      await tester.pump();
      expect(await exit, isFalse);
      source.userId = chatOther;
      source.accounts.add(chatOther);
      picked.complete(
        XFile.fromData(
          Uint8List.fromList(headers['pdf']!),
          name: 'private.pdf',
          path: 'private.pdf',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('private.pdf'), findsNothing);
      expect(source.sends, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
