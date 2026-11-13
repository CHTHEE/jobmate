import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/chat/chat_models.dart';
import 'package:jobmate/features/chat/chat_pending_store.dart';
import 'package:jobmate/features/chat/chat_repository.dart';
import 'package:jobmate/features/chat/chat_source.dart';
import 'package:jobmate/features/chat/debug/chat_runtime_controller.dart';
import 'package:jobmate/features/chat/debug/chat_runtime_page.dart';
import 'package:jobmate/features/chat/debug/chat_runtime_scope.dart';
import 'package:jobmate/features/notifications/notifications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const conversation = '20000000-0000-0000-0000-000000000001';
const message = '30000000-0000-0000-0000-000000000001';

class RuntimeSource implements ChatSource {
  @override
  String? userId = actor;
  final auth = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accountChanges => auth.stream;
  int reads = 0, writes = 0;
  String? applicationWritten;
  PostgrestException? createFailure;
  final sent = <PendingChatSend>[];
  final commits = <String, Map<String, Object?>>{};
  final readMarks = <(String?, String, String)>[];
  int? beforeSequence;
  ChatConversationCursor? before;
  Object? conversationResult = [
    {
      'conversation_id': conversation,
      'application_id': message,
      'job_id': message,
      'job_title': 'Private job title',
      'company_name': 'Private company',
      'worker_name': 'Private name',
      'application_status': 'submitted',
      'created_at': '2026-11-13T00:00:00Z',
      'activity_at': '2026-11-13T00:00:00Z',
      'last_message_preview': null,
      'last_message_at': null,
      'last_sequence': 0,
      'unread_count': 0,
      'can_send': true,
      'read_only_reason': null,
    },
  ];
  Object? messageResult = [
    {
      'message_id': message,
      'conversation_id': conversation,
      'sender_id': actor,
      'sender_name': 'Private name',
      'body': 'Private message body',
      'sent_at': '2026-11-13T00:00:00Z',
      'sequence': 2,
    },
  ];
  Completer<Object?>? hold;
  @override
  Future<Object?> conversations({
    required int limit,
    ChatConversationCursor? before,
    String? conversationId,
  }) async {
    reads++;
    this.before = before;
    return hold == null ? conversationResult : await hold!.future;
  }

  @override
  Future<Object?> messages(
    String conversationId, {
    required int limit,
    int? beforeSequence,
  }) async {
    reads++;
    this.beforeSequence = beforeSequence;
    if (conversationId == other) {
      throw const PostgrestException(
        message: 'SECRET SERVER DETAILS',
        code: '42501',
      );
    }
    return beforeSequence == 1 ? [] : messageResult;
  }

  @override
  Future<Object?> getOrCreate(String applicationId) async {
    writes++;
    applicationWritten = applicationId;
    if (createFailure != null) throw createFailure!;
    return conversation;
  }

  @override
  Future<Object?> send(PendingChatSend pending) async {
    writes++;
    sent.add(pending);
    final key = '${pending.actorId}:${pending.requestId}';
    final row = commits.putIfAbsent(
      key,
      () => {
        'message_id': pending.requestId,
        'conversation_id': pending.conversationId,
        'sender_id': pending.actorId,
        'body': pending.body,
        'sent_at': '2026-11-13T00:00:00Z',
        'sequence': commits.length + 1,
      },
    );
    return [row];
  }

  @override
  Future<Object?> markRead(String conversationId, String messageId) async {
    writes++;
    readMarks.add((userId, conversationId, messageId));
    return 2;
  }

  void switchTo(String? value) {
    userId = value;
    auth.add(value);
  }
}

class NoWriteStore implements ChatPendingStore {
  int operations = 0;
  @override
  Future<List<PendingChatSend>> load(String actorId) async {
    operations++;
    return [];
  }

  @override
  Future<PendingChatSend> prepare(PendingChatSend candidate) async {
    operations++;
    return candidate;
  }

  @override
  Future<void> remove(PendingChatSend confirmed) async {
    operations++;
  }
}

class TrialStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class FakeRealtime implements ChatRuntimeRealtime {
  int stops = 0;
  void Function(String)? status;
  void Function(Map<String, Object?>)? event;
  @override
  void start(
    String conversationId,
    void Function(String) status,
    void Function(Map<String, Object?>) event,
  ) {
    this.status = status;
    this.event = event;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  late RuntimeSource source;
  late NoWriteStore store;
  late FakeRealtime realtime;
  late ChatRuntimeController controller;
  bool pageOwnsController = false;
  int accountReads = 0, applicationReads = 0;
  ChatRuntimeController scopedController({
    TrialStorage? disk,
    String? role,
    String status = 'active',
  }) {
    late ChatRuntimeController scoped;
    final guarded = ScopedChatRuntimeSource(
      source,
      writePermit: () => scoped.writesEnabled,
    );
    scoped = ChatRuntimeController(
      repository: ChatRepository(
        source: guarded,
        pendingStore: LocalChatPendingStore(
          storage: disk ?? TrialStorage(),
          projectUrl: 'https://existing-project.supabase.co',
        ),
        requestId: () => approvedChatRequestId(source.userId),
        delay: (_) async {},
      ),
      readAccount: () async => {
        'user_id': source.userId,
        'role': role ?? approvedChatRole(source.userId) ?? 'job_seeker',
        'status': status,
      },
      readApplications: () async => [],
      realtime: realtime,
    );
    return scoped;
  }

  void useScoped({TrialStorage? disk, String? role, String status = 'active'}) {
    controller.dispose();
    source.userId = approvedChatSeeker;
    final row = (source.conversationResult as List).first as Map;
    row['application_id'] = approvedChatApplication;
    controller = scopedController(disk: disk, role: role, status: status);
  }

  setUp(() {
    pageOwnsController = false;
    source = RuntimeSource();
    store = NoWriteStore();
    realtime = FakeRealtime();
    accountReads = applicationReads = 0;
    controller = ChatRuntimeController(
      repository: ChatRepository(source: source, pendingStore: store),
      readAccount: () async {
        accountReads++;
        return {'user_id': actor, 'role': 'job_seeker', 'status': 'active'};
      },
      readApplications: () async {
        applicationReads++;
        return [];
      },
      realtime: realtime,
    );
  });
  tearDown(() async {
    if (!pageOwnsController) controller.dispose();
    await source.auth.close();
  });

  test(
    'no automatic queries; write methods reject before repository or storage',
    () async {
      expect(source.reads, 0);
      expect(accountReads, 0);
      expect(applicationReads, 0);
      expect(controller.writesEnabled, isFalse);
      controller.selectedApplication = message;
      controller.selectConversation(conversation);
      await expectLater(controller.createConversation(), throwsStateError);
      await expectLater(controller.send('do not send'), throwsStateError);
      await expectLater(controller.retry(), throwsStateError);
      await expectLater(controller.markRead(message), throwsStateError);
      expect(source.writes, 0);
      expect(store.operations, 0);
    },
  );

  test('actual repository typed pages, paired cursors, empty history boundary and evidence', () async {
    await controller.loadIdentity();
    await controller.loadApplications();
    await controller.loadConversations();
    expect(controller.conversationPage!.items.single, isA<ChatConversation>());
    source.conversationResult = [];
    await controller.loadConversations(next: true);
    expect(source.before!.conversationId, conversation);
    expect(controller.conversationPage!.items, isEmpty);
    controller.selectConversation(conversation);
    await controller.loadMessages();
    expect(controller.messagePage!.items.single, isA<ChatMessage>());
    source.messageResult = [];
    await controller.loadMessages(next: true);
    expect(source.beforeSequence, 2);
    await controller.loadMessages(emptyBoundary: true);
    expect(source.beforeSequence, 1);
    final evidence = controller.evidenceJson;
    expect(jsonDecode(evidence)['records'], isNotEmpty);
    for (final secret in [
      'Private name',
      'Private company',
      'Private job title',
      'Private message body',
      'access_token',
      'refresh_token',
      'Authorization',
    ]) {
      expect(evidence, isNot(contains(secret)));
    }
    expect(source.writes, 0);
    expect(store.operations, 0);
  });

  test('real error type/code and strict parse failure recorded without raw server details', () async {
    controller.selectConversation(other);
    await controller.loadMessages();
    expect(controller.error, contains('42501'));
    expect(controller.evidenceJson, contains('42501'));
    expect(controller.evidenceJson, isNot(contains('SECRET SERVER DETAILS')));
    source.conversationResult = [
      {'conversation_id': conversation},
    ];
    await controller.loadConversations();
    expect(controller.error, contains('Typed parsing failed'));
    expect(controller.evidenceJson, contains('"typed_parsing_failed": true'));
  });

  test(
    'account changes clear typed data and discard A-B-A pending response',
    () async {
      controller.selectConversation(conversation);
      await controller.loadMessages();
      source.hold = Completer<Object?>();
      final loading = controller.loadConversations();
      source.switchTo(other);
      source.switchTo(actor);
      source.hold!.complete([]);
      await loading;
      expect(controller.messagePage, isNull);
      expect(controller.conversationPage, isNull);
      expect(controller.selectedConversation, isNull);
      expect(controller.busy, isFalse);
      expect(controller.evidenceJson, isNot(contains(message)));
      source.switchTo(null);
      await controller.loadIdentity();
      expect(accountReads, 0);
      expect(controller.error, contains('Sign in'));
    },
  );

  test('observer reports real callback metadata; old selection/auth callbacks ignored', () async {
    controller.selectConversation(conversation);
    await controller.startRealtime();
    realtime.status!('subscribed');
    expect(controller.realtimeStatus, 'subscribed');
    expect(controller.evidenceJson, isNot(contains('observed_not_reconciled')));
    realtime.event!({'message_id': message, 'sequence': 2});
    expect(controller.evidenceJson, contains('observed_not_reconciled'));
    final oldEvent = realtime.event!;
    controller.selectConversation(other);
    final before = controller.evidenceJson;
    oldEvent({'message_id': other});
    expect(controller.evidenceJson, before);
    source.switchTo(null);
    oldEvent({'message_id': message});
    expect(controller.evidenceJson, isNot(contains(message)));
    expect(realtime.stops, greaterThan(0));
  });

  testWidgets(
    'screen has explicit reads, locked writes, empty state and copy; narrow layout',
    (tester) async {
      pageOwnsController = true;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: ChatRuntimePage(controller: controller)),
      );
      expect(source.reads, 0);
      source.conversationResult = [];
      await tester.tap(find.text('Load conversations'));
      await tester.pumpAndSettle();
      expect(find.text('Empty conversation page.'), findsOneWidget);
      for (final label in [
        'Create / reuse approved conversation',
        'Send agreed message',
        'Retry same UUID/body',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, label),
        );
        expect(button.onPressed, isNull);
      }
      await tester.scrollUntilVisible(
        find.text('Copy evidence JSON'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Copy evidence JSON'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('approved writes require exact active identity and application/conversation scope', () async {
    useScoped();
    expect(controller.writesEnabled, isFalse);
    await expectLater(controller.createConversation(), throwsStateError);
    await controller.loadIdentity();
    expect(controller.writesEnabled, isTrue);
    controller.selectedApplication = message;
    await expectLater(controller.createConversation(), throwsStateError);
    expect(source.writes, 0);
    controller.selectedApplication = null;
    await controller.createConversation();
    expect(source.applicationWritten, approvedChatApplication);
    expect(controller.canWriteConversation, isTrue);
    await expectLater(controller.send('unapproved text'), throwsStateError);
    controller.selectConversation(other);
    expect(controller.canWriteConversation, isFalse);
    await expectLater(
      controller.send(approvedChatBody(approvedChatSeeker)!),
      throwsStateError,
    );
    await expectLater(controller.retry(), throwsStateError);
    await expectLater(controller.markRead(message), throwsStateError);
    final boundary = controller.repository.source;
    await expectLater(boundary.getOrCreate(other), throwsStateError);
    for (final pending in [
      PendingChatSend(
        actorId: approvedChatSeeker,
        conversationId: other,
        requestId: approvedChatRequestId(approvedChatSeeker),
        body: approvedChatBody(approvedChatSeeker)!,
      ),
      PendingChatSend(
        actorId: approvedChatSeeker,
        conversationId: conversation,
        requestId: message,
        body: approvedChatBody(approvedChatSeeker)!,
      ),
      PendingChatSend(
        actorId: approvedChatSeeker,
        conversationId: conversation,
        requestId: approvedChatRequestId(approvedChatSeeker),
        body: 'changed',
      ),
      PendingChatSend(
        actorId: approvedChatEmployer,
        conversationId: conversation,
        requestId: approvedChatRequestId(approvedChatEmployer),
        body: approvedChatBody(approvedChatEmployer)!,
      ),
    ]) {
      await expectLater(boundary.send(pending), throwsStateError);
    }
    expect(source.writes, 1);
    expect(source.sent, isEmpty);
    source.switchTo(other);
    await controller.loadIdentity();
    expect(controller.writesEnabled, isFalse);
    await expectLater(
      boundary.getOrCreate(approvedChatApplication),
      throwsStateError,
    );
  });

  test('one stable UUID/body per participant across repeated send, retry, restart and empty storage', () async {
    useScoped();
    await controller.loadIdentity();
    await controller.createConversation();
    await controller.send(approvedChatBody(approvedChatSeeker)!);
    await controller.send(approvedChatBody(approvedChatSeeker)!);
    await controller.retry();
    expect(source.commits.length, 1);
    final firstKey = source.sent.first.requestId;
    expect(source.sent.every((row) => row.requestId == firstKey), isTrue);
    expect(
      controller.evidenceJson,
      contains('"same_receipt_as_previous": true'),
    );
    // Reconstruct with completely fresh local storage, as on another device.
    controller.dispose();
    controller = scopedController();
    await controller.loadIdentity();
    await controller.createConversation();
    await controller.send(approvedChatBody(approvedChatSeeker)!);
    expect(source.sent.last.requestId, firstKey);
    expect(source.commits.length, 1);
    source.switchTo(approvedChatEmployer);
    await controller.loadIdentity();
    await controller.createConversation();
    await controller.send(approvedChatBody(approvedChatEmployer)!);
    await controller.retry();
    expect(source.commits.length, 2);
    expect(source.sent.last.requestId, isNot(firstKey));
    expect(
      source.sent.every(
        (row) =>
            row.requestId == approvedChatRequestId(row.actorId) &&
            row.body == approvedChatBody(row.actorId),
      ),
      isTrue,
    );
    expect(
      controller.evidenceJson,
      isNot(contains(approvedChatBody(approvedChatSeeker)!)),
    );
    expect(
      controller.evidenceJson,
      isNot(contains(approvedChatBody(approvedChatEmployer)!)),
    );
  });

  test(
    'wrong role or inactive approved identity cannot unlock writes',
    () async {
      useScoped(role: 'employer');
      await controller.loadIdentity();
      expect(controller.writesEnabled, isFalse);
      await expectLater(controller.createConversation(), throwsStateError);
      useScoped(status: 'suspended');
      await controller.loadIdentity();
      expect(controller.writesEnabled, isFalse);
      await expectLater(controller.createConversation(), throwsStateError);
      expect(source.writes, 0);
    },
  );

  test(
    'access/read-only errors stop trial; no auto unlock after a later read',
    () async {
      useScoped();
      await controller.loadIdentity();
      source.createFailure = const PostgrestException(
        message: 'private details',
        code: '55000',
      );
      await controller.createConversation();
      expect(controller.trialStopped, isTrue);
      expect(controller.writesEnabled, isFalse);
      expect(controller.error, contains('55000'));
      source.createFailure = null;
      await controller.loadIdentity();
      await expectLater(controller.createConversation(), throwsStateError);
      expect(source.writes, 1);
    },
  );

  test(
    'read-only capability or wrong returned application stops before sending',
    () async {
      useScoped();
      await controller.loadIdentity();
      final row = (source.conversationResult as List).first as Map;
      row['can_send'] = false;
      row['read_only_reason'] = 'company_unverified';
      await controller.createConversation();
      expect(controller.trialStopped, isTrue);
      expect(source.sent, isEmpty);
      controller.dispose();
      controller = scopedController();
      await controller.loadIdentity();
      row['can_send'] = true;
      row['read_only_reason'] = null;
      row['application_id'] = message;
      await controller.createConversation();
      expect(controller.trialStopped, isTrue);
      expect(source.sent, isEmpty);
    },
  );

  test('conflicting saved request fails closed without minting or dispatching a new identity', () async {
    final disk = TrialStorage();
    useScoped(disk: disk);
    await controller.loadIdentity();
    await controller.createConversation();
    await controller.repository.pendingStore.prepare(
      PendingChatSend(
        actorId: approvedChatSeeker,
        conversationId: conversation,
        requestId: message,
        body: approvedChatBody(approvedChatSeeker)!,
      ),
    );
    await controller.send(approvedChatBody(approvedChatSeeker)!);
    expect(controller.trialStopped, isTrue);
    expect(source.sent, isEmpty);
    expect(
      (await controller.repository.pendingStore.load(approvedChatSeeker))
          .single
          .requestId,
      message,
    );
  });

  test('read cursor limited to retrieved approved history and own authenticated identity', () async {
    useScoped();
    await controller.loadIdentity();
    await controller.createConversation();
    await expectLater(controller.markRead(message), throwsStateError);
    await controller.loadMessages();
    await controller.markRead(message);
    expect(source.readMarks.single, (
      approvedChatSeeker,
      conversation,
      message,
    ));
    await expectLater(controller.markRead(other), throwsStateError);
    controller.selectConversation(other);
    await expectLater(controller.markRead(message), throwsStateError);
    expect(source.readMarks.length, 1);
  });

  test('account changes during fresh scope verification stop send before storage/network', () async {
    useScoped();
    await controller.loadIdentity();
    await controller.createConversation();
    source.hold = Completer<Object?>();
    final sending = controller.send(approvedChatBody(approvedChatSeeker)!);
    source.switchTo(approvedChatEmployer);
    source.switchTo(approvedChatSeeker);
    source.hold!.complete(source.conversationResult);
    await sending;
    expect(source.sent, isEmpty);
    expect(controller.writesEnabled, isFalse);
    expect(controller.pending, isNull);
  });

  test('notification snapshots export metadata only without changing notification state', () async {
    controller.dispose();
    controller = ChatRuntimeController(
      repository: ChatRepository(source: source, pendingStore: store),
      readAccount: () async => {},
      readApplications: () async => [],
      readNotifications: () async => [
        JobMateNotification({
          'notification_id': message,
          'notification_type': 'chat_message',
          'title': 'PRIVATE TITLE',
          'message': 'PRIVATE BODY',
          'created_at': '2026-11-13T00:00:00Z',
          'read_at': null,
        }),
      ],
    );
    await controller.loadNotifications();
    expect(controller.evidenceJson, contains('chat_message'));
    expect(controller.evidenceJson, contains(message));
    expect(controller.evidenceJson, isNot(contains('PRIVATE')));
    expect(source.writes, 0);
  });

  testWidgets(
    'approved participant has fixed-message buttons and exports actual runtime receipts',
    (tester) async {
      useScoped();
      pageOwnsController = true;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: ChatRuntimePage(controller: controller)),
      );
      Future<void> click(String label) async {
        final finder = find.widgetWithText(OutlinedButton, label);
        await tester.scrollUntilVisible(
          finder,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await click('Check account');
      await click('Create / reuse approved conversation');
      expect(controller.canWriteConversation, isTrue);
      await click('Send agreed message');
      await click('Retry same UUID/body');
      expect(source.commits.length, 1);
      expect(source.sent.first.body, approvedChatBody(approvedChatSeeker));
      await click('Copy evidence JSON');
      expect(copied, contains(approvedChatRequestId(approvedChatSeeker)));
      expect(copied, isNot(contains(approvedChatBody(approvedChatSeeker)!)));
      expect(jsonDecode(copied!)['writes_enabled'], isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
