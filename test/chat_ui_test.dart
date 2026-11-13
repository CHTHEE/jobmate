import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/chat/chat_application_button.dart';
import 'package:jobmate/features/chat/chat_dependencies.dart';
import 'package:jobmate/features/chat/chat_page.dart';
import 'package:jobmate/features/chat/chat_ui_controller.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/chat_ui.dart';

void main() {
  late ChatFixtureSource source;
  late ChatFixtureStorage storage;
  late ChatFixtureFeed feed;
  late ChatUiController ui;
  bool pageOwns = false;
  setUp(() async {
    source = ChatFixtureSource();
    storage = ChatFixtureStorage();
    feed = ChatFixtureFeed();
    ui = fixtureChatUi(source: source, storage: storage, feed: feed);
    pageOwns = false;
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    if (!pageOwns) ui.dispose();
    await source.accounts.close();
  });
  test('production page factories share one pending-store queue per project origin', () async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(
      sharedChatPendingStore('https://offline.example/'),
      same(sharedChatPendingStore('https://offline.example')),
    );
    expect(
      sharedChatPendingStore('https://offline.example'),
      isNot(same(sharedChatPendingStore('https://other.example'))),
    );
    await Future<void>.delayed(Duration.zero);
  });
  test('read cursor skips own messages, hidden requests and repeated incoming targets', () async {
    await ui.start(chatConversation);
    await ui.markRead(
      ui.messages.firstWhere((message) => message.senderId == chatActor),
    );
    expect(source.marks, 0);
    final incoming = ui.messages.firstWhere(
      (message) => message.senderId != chatActor,
    );
    ui.setVisible(false);
    await ui.markRead(incoming);
    expect(source.marks, 0);
    ui.setVisible(true);
    await Future<void>.delayed(Duration.zero);
    await ui.markRead(incoming);
    await ui.markRead(incoming);
    expect(source.marks, 1);
  });
  test('automatic read failure does not turn successful message history into a thread error', () async {
    await ui.start(chatConversation);
    source.failure = const PostgrestException(
      message: 'private backend details',
      code: '55P03',
    );
    await ui.markRead(
      ui.messages.firstWhere((message) => message.senderId != chatActor),
    );
    expect(ui.readError, isNotNull);
    expect(ui.readError, isNot(contains('private backend details')));
    expect(ui.threadError, isNull);
    expect(ui.reading, false);
    expect(ui.selected!.canSend, true);
  });
  testWidgets(
    'hidden application fetches history without automatic read, then reads displayed incoming on resume',
    (tester) async {
      await ui.start(chatConversation);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      pageOwns = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(controller: ui, conversationId: chatConversation),
        ),
      );
      await tester.pumpAndSettle();
      expect(ui.messages, isNotEmpty);
      expect(source.marks, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(source.marks, 1);
      expect(find.text('Mark read'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('cached offscreen incoming messages are not marked read', (
    tester,
  ) async {
    source.history = [
      {...messageRow(2), 'body': List.filled(600, 'long').join(' ')},
      messageRow(1),
    ];
    pageOwns = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(controller: ui, conversationId: chatConversation),
      ),
    );
    await tester.pumpAndSettle();
    expect(ui.messages.length, 2);
    expect(source.marks, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'short sent and received bubbles shrink to content and retain alignment',
    (tester) async {
      pageOwns = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(controller: ui, conversationId: chatConversation),
        ),
      );
      await tester.pumpAndSettle();
      final sent = find
          .ancestor(of: find.text('Message 2'), matching: find.byType(Card))
          .first;
      final received = find
          .ancestor(of: find.text('Message 1'), matching: find.byType(Card))
          .first;
      expect(tester.getSize(sent).width, lessThan(240));
      expect(tester.getSize(received).width, lessThan(240));
      expect(
        tester.getTopLeft(sent).dx,
        greaterThan(tester.getTopLeft(received).dx),
      );
      expect(find.text('You'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'desktop list uses real initials and a useful empty conversation state',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      pageOwns = true;
      await tester.pumpWidget(MaterialApp(home: ChatPage(controller: ui)));
      await tester.pumpAndSettle();
      expect(find.text('Select a conversation'), findsOneWidget);
      expect(find.text('EC'), findsOneWidget);
      expect(find.text('Example company'), findsOneWidget);
      expect(find.text('Event assistant'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.work_outline &&
              widget.size == 12,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final employer in [false, true]) {
    testWidgets(
      'long participant/job header stays compact at 320 for employer=$employer',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        source.inbox = [
          {
            ...conversationRow(),
            'company_name': 'Very Long Company Name ' * 8,
            'worker_name': 'Very Long Applicant Name ' * 8,
            'job_title': 'Long existing job title ' * 8,
          },
        ];
        pageOwns = true;
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              controller: ui,
              conversationId: chatConversation,
              employer: employer,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('VN'), findsOneWidget);
        expect(find.text('Hired'), findsOneWidget);
        expect(find.byTooltip('Conversations'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'actual message days have one separator and extension of a loaded day adds none',
    (tester) async {
      final today = DateTime(2026, 11, 13, 10).toUtc().toIso8601String();
      final previous = DateTime(2026, 11, 12, 10).toUtc().toIso8601String();
      source.inbox = [conversationRow(last: 4)];
      source.history = [
        {...messageRow(4), 'sent_at': today},
        {...messageRow(3), 'sent_at': today},
        {...messageRow(2), 'sent_at': previous},
      ];
      pageOwns = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(controller: ui, conversationId: chatConversation),
        ),
      );
      await tester.pumpAndSettle();
      final dates = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('chat-date-'),
      );
      expect(dates, findsNWidgets(2));
      source.history.add({...messageRow(1), 'sent_at': previous});
      await ui.refreshThread();
      await tester.pumpAndSettle();
      expect(dates, findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('list/direct history reads never create/send/mark; explicit mark reloads unread', () async {
    await ui.start(chatConversation);
    expect(ui.selected!.id, chatConversation);
    expect(ui.messages.length, 2);
    expect(source.creates, 0);
    expect(source.sends, isEmpty);
    expect(source.marks, 0);
    await ui.markRead(ui.messages.last);
    expect(source.marks, 1);
    expect(ui.conversations.single.unreadCount, 0);
  });
  test(
    'conversation paired cursor pages merge uniquely in activity/UUID order',
    () async {
      source.inbox = List.generate(65, (i) => conversationRow(id: 20 + i));
      await ui.start();
      expect(ui.conversations.length, 50);
      final cursor = ui.nextConversation!;
      await ui.loadConversations(older: true);
      expect(source.lastCursor, same(cursor));
      expect(ui.conversations.length, 65);
      expect(ui.conversations.map((row) => row.id).toSet().length, 65);
      expect(ui.nextConversation, isNull);
    },
  );
  test('history paging and event reconciliation deduplicate, retain oldest cursor and repair large gaps', () async {
    source.history = List.generate(70, (i) => messageRow(70 - i));
    await ui.start(chatConversation);
    expect(ui.messages.length, 50);
    expect(ui.nextSequence, 21);
    await ui.refreshThread(older: true);
    expect(ui.messages.length, 70);
    expect(ui.nextSequence, isNull);
    await ui.refreshThread();
    expect(ui.messages.length, 70);
    expect(ui.nextSequence, isNull);
    source.history.insert(0, messageRow(71));
    feed.callback!();
    await Future<void>.delayed(Duration.zero);
    expect(ui.messages.length, 71);
    expect(ui.messages.first.sequence, 71);
    source.history = List.generate(200, (i) => messageRow(200 - i));
    await ui.refreshThread();
    expect(ui.messages.length, 50);
    expect(ui.nextSequence, 151);
    await ui.refreshThread(older: true);
    expect(ui.messages.length, 100);
    expect(ui.messages.last.sequence, 101);
  });
  test('lost send reply retains exact body and UUID; retry confirms a single stored message', () async {
    await ui.start(chatConversation);
    ui.setDraft(' hello 😀 ');
    source.onSend = (pending) async {
      source.commit(pending);
      throw TimeoutException('reply lost');
    };
    await ui.send();
    final saved = ui.pending!;
    expect(ui.draft, ' hello 😀 ');
    expect(ui.needsExitConfirmation, isTrue);
    expect(source.commits.length, 1);
    expect(ui.sendError, contains('not confirmed'));
    ui.setDraft('different');
    expect(ui.draft, saved.body);
    source.onSend = null;
    await ui.send(retry: true);
    expect(source.sends.last.requestId, saved.requestId);
    expect(source.commits.length, 1);
    expect(ui.pending, isNull);
    expect(ui.draft, isEmpty);
  });
  test(
    'pending records restore after reconstruction without automatic replay',
    () async {
      await ui.start(chatConversation);
      ui.setDraft('saved');
      source.onSend = (_) async => throw TimeoutException('lost');
      await ui.send();
      final saved = ui.pending!;
      final count = source.sends.length;
      ui.dispose();
      ui = fixtureChatUi(source: source, storage: storage, feed: feed);
      await ui.start(chatConversation);
      expect(source.sends.length, count);
      expect(ui.pending!.requestId, saved.requestId);
      expect(ui.draft, saved.body);
    },
  );
  test('invalid bodies, recovery failure and read-only capabilities do not dispatch sends', () async {
    await ui.start(chatConversation);
    ui.setDraft('\u00a0 \n');
    await ui.send();
    expect(source.sends, isEmpty);
    expect(ui.sendError, contains('4000'));
    storage.fail = true;
    await ui.start(chatConversation);
    ui.setDraft('body');
    await ui.send();
    expect(ui.recoveryFailed, isTrue);
    expect(source.sends, isEmpty);
    storage.fail = false;
    await ui.start(chatConversation);
    source.inbox = [conversationRow(canSend: false)];
    await ui.refreshThread();
    await ui.send();
    expect(source.sends, isEmpty);
    await ui.markRead(
      ui.messages.firstWhere((message) => message.senderId != chatActor),
    );
    expect(source.marks, 1);
  });
  test('auth switches erase state/drafts; stale A-B-A responses and callbacks cannot repopulate', () async {
    await ui.start(chatConversation);
    ui.setDraft('private draft');
    final oldEvent = feed.callback!;
    source.hold = Completer<Object?>();
    final load = ui.loadConversations();
    source.changeAccount(chatOther);
    source.changeAccount(chatActor);
    source.hold!.complete([conversationRow()]);
    await load;
    oldEvent();
    await Future<void>.delayed(Duration.zero);
    expect(ui.conversations, isEmpty);
    expect(ui.messages, isEmpty);
    expect(ui.draft, isEmpty);
    expect(ui.needsExitConfirmation, isFalse);
    expect(ui.pendingCount, 0);
    expect(feed.stops, greaterThan(0));
  });
  test('denied refresh removes cached private data and invalid UUID never opens stale history', () async {
    await ui.start(chatConversation);
    source.failure = const PostgrestException(
      message: 'private backend details',
      code: '42501',
    );
    await ui.refresh();
    expect(ui.conversations, isEmpty);
    expect(ui.messages, isEmpty);
    expect(ui.selected, isNull);
    expect(ui.threadError, isNot(contains('private backend details')));
    source.failure = null;
    await ui.open(chatConversation);
    await ui.open('bad-id');
    expect(ui.selected, isNull);
    expect(ui.messages, isEmpty);
  });
  test('hidden routes stop subscriptions and resume reconciles history without writes', () async {
    await ui.start(chatConversation);
    ui.setVisible(false);
    expect(feed.stops, greaterThan(0));
    source.history.insert(0, messageRow(3));
    ui.setVisible(true);
    await Future<void>.delayed(Duration.zero);
    expect(ui.messages.first.sequence, 3);
    expect(source.sends, isEmpty);
    expect(source.marks, 0);
  });

  for (final width in [320.0, 768.0, 1440.0]) {
    for (final employer in [false, true]) {
      testWidgets(
        'real thread $employer at $width handles text scale and keyboard without overflow',
        (tester) async {
          pageOwns = true;
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => ChatPage(
                  employer: employer,
                  conversationId: chatConversation,
                  controller: ui,
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            MaterialApp.router(
              theme: JobMateTheme.light(),
              routerConfig: router,
              builder: (_, child) => MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: TextScaler.linear(1.3),
                  viewInsets: const EdgeInsets.only(bottom: 220),
                ),
                child: child!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            ui.selected,
            isNotNull,
            reason:
                'list=${ui.listError}; thread=${ui.threadError}; id=${ui.selectedId}; reads=${source.reads}; actor=${ui.actorId}',
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Message',
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText && widget.data == 'Message 2',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('simulated'), findsNothing);
          expect(source.sends, isEmpty);
          expect(
            source.marks,
            1,
          ); // Incoming bubble displayed in active thread.
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets(
    'draft exit confirmation protects input and saved retry is recoverable',
    (tester) async {
      pageOwns = true;
      final pageKey = GlobalKey<ChatPageState>();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ChatPage(
              key: pageKey,
              conversationId: chatConversation,
              controller: ui,
            ),
            onExit: (_, _) => pageKey.currentState!.confirmExit(),
          ),
          GoRoute(
            path: '/other',
            builder: (_, _) => const Scaffold(body: Text('Other page')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(ui.selected, isNotNull, reason: ui.threadError);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Message',
        ),
        'unsent draft',
      );
      router.go('/other');
      await tester.pumpAndSettle();
      expect(find.text('Leave this conversation?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(ui.draft, 'unsent draft');
      expect(find.text('Other page'), findsNothing);
      router.go('/other');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Other page'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Message application button creates only on click with exact application',
    (tester) async {
      int allocations = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: ChatApplicationButton(
                applicationId: chatApplication,
                createRepository: () {
                  allocations++;
                  return fixtureChatUi(source: source).repository;
                },
              ),
            ),
          ),
          GoRoute(
            path: '/messages/:conversationId',
            builder: (_, _) => const Scaffold(body: Text('Opened thread')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(allocations, 0);
      expect(source.creates, 0);
      await tester.tap(find.text('Message Employer'));
      await tester.pumpAndSettle();
      expect(allocations, 1);
      expect(source.creates, 1);
      expect(find.text('Opened thread'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
