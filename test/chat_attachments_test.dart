import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/chat/chat_attachment_models.dart';
import 'package:jobmate/features/chat/chat_attachment_draft.dart';
import 'package:jobmate/features/chat/chat_attachments.dart';
import 'package:jobmate/features/chat/chat_attachment_card.dart';
import 'package:jobmate/features/chat/chat_models.dart';
import 'package:jobmate/features/chat/chat_file_digest.dart';
import 'package:jobmate/features/chat/chat_page.dart';

import 'fixtures/chat_ui.dart';

class FakeAttachments implements ChatAttachmentGateway {
  @override
  String? actorId = chatActor;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get accounts => changes.stream;
  Map<String, dynamic>? row;
  int chunks = 0, commits = 0, notifications = 0, reserves = 0, aborts = 0;
  bool lostReply = false, outage = false, reject = false;
  bool lostValidationReply = false;
  int validations = 0;
  int downloads = 0;
  void Function()? onChunk;
  @override
  void cancelTransfers() {
    aborts++;
  }

  ChatAttachment value() => ChatAttachment.fromRow(row!);
  @override
  Future<ChatAttachment> reserve(
    String conversation,
    String request,
    String id,
    ChatAttachmentDraft file,
    String? caption,
  ) async {
    reserves++;
    row ??= {
      'attachment_id': id,
      'conversation_id': conversation,
      'sender_id': actorId,
      'client_request_id': request,
      'message_id': null,
      'caption': caption,
      'original_name': file.name,
      'mime_type': file.mimeType,
      'expected_sha256': file.digest,
      'size_bytes': file.bytes.length,
      'state': 'pending',
      'validation_scope': 'basic-type-validation-no-antivirus-v1',
      'storage_path': null,
    };
    return value();
  }

  @override
  Future<ChatAttachment> status(String id) async => value();
  @override
  Future<List<ChatAttachment>> pending(String conversation) async =>
      row == null ? [] : [value()];
  @override
  Future<void> chunk(String id, int index, Uint8List bytes) async {
    chunks++;
    onChunk?.call();
  }

  @override
  Future<ChatAttachment> validate(String id) async {
    validations++;
    if (outage) throw StateError('Content validation unavailable');
    row!['state'] = reject ? 'rejected' : 'validated';
    if (lostValidationReply) {
      lostValidationReply = false;
      throw StateError(
        'Empty finalization response after successful validation',
      );
    }
    return value();
  }

  @override
  Future<ChatMessage> send(String id) async {
    if (row!['state'] != 'committed') {
      commits++;
      notifications++;
      row!['state'] = 'committed';
      row!['message_id'] = chatId(77);
      row!['storage_path'] = '$chatConversation/$chatActor/$id/file';
    }
    if (lostReply) {
      lostReply = false;
      throw StateError('Lost response after commit');
    }
    return ChatMessage.fromRow({
      ...messageRow(3),
      'message_id': chatId(77),
      'sender_id': chatActor,
      'caption': row!['caption'],
      'body': row!['caption'] ?? 'Attachment: ${row!['original_name']}',
      'attachment': {...row!},
    }, sentResult: true);
  }

  @override
  Future<Uri> download(ChatAttachment attachment) async {
    downloads++;
    return Uri.parse('https://example.invalid/private-test-only');
  }
}

ChatAttachmentDraft draft({int length = 10}) => ChatAttachmentDraft.select(
  'a.pdf',
  Uint8List(length)..setAll(0, [37, 80, 68, 70, 45]),
);
void main() {
  test('SHA-256 known vectors and padding boundary', () {
    expect(
      chatFileDigest(Uint8List(0)),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      chatFileDigest(Uint8List.fromList('abc'.codeUnits)),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      chatFileDigest(
        Uint8List.fromList(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'.codeUnits,
        ),
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });
  late FakeAttachments gateway;
  late ChatAttachmentsController controller;
  setUp(() {
    gateway = FakeAttachments();
    controller = ChatAttachmentsController(gateway);
  });
  tearDown(() async {
    controller.dispose();
    await gateway.changes.close();
  });
  test(
    'approved attachment feature defaults true',
    () => expect(chatAttachmentsEnabled, true),
  );
  test('validated reservation after lost reply retries same identity without upload or validation', () async {
    controller.select(draft());
    gateway.lostValidationReply = true;
    await controller.run(chatConversation, '');
    final attachment = gateway.row!['attachment_id'];
    final request = gateway.row!['client_request_id'];
    expect(controller.phase, 'Not confirmed');
    expect(gateway.row!['state'], 'validated');
    expect(gateway.commits, 0);
    await controller.run(chatConversation, '');
    await controller.run(chatConversation, '');
    expect(controller.phase, 'Sent');
    expect(controller.receipt!.attachment!.id, attachment);
    expect(controller.receipt!.attachment!.requestId, request);
    expect(gateway.reserves, 1);
    expect(gateway.chunks, 1);
    expect(gateway.validations, 1);
    expect(gateway.commits, 1);
    expect(gateway.notifications, 1);
  });
  testWidgets(
    'image preview reauthorizes, closes safely and hides on account switch',
    (tester) async {
      controller.select(draft());
      await controller.run(chatConversation, '');
      final image = ChatAttachment.fromRow({
        ...gateway.row!,
        'original_name': 'photo.png',
        'mime_type': 'image/png',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatAttachmentCard(attachment: image, gateway: gateway),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.downloads, 1);
      await tester.tap(find.byTooltip('Open image preview'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(gateway.downloads, 2);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      gateway.actorId = chatId(999);
      gateway.changes.add(gateway.actorId);
      await tester.pumpAndSettle();
      expect(find.text('Image unavailable.'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.tap(find.byTooltip('Close image preview'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final format in ['pdf', 'docx', 'xlsx']) {
    testWidgets('$format is a download card without a document viewer', (
      tester,
    ) async {
      controller.select(draft());
      await controller.run(chatConversation, '');
      final document = ChatAttachment.fromRow({
        ...gateway.row!,
        'original_name': 'document.$format',
        'mime_type': switch (format) {
          'pdf' => 'application/pdf',
          'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          _ =>
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatAttachmentCard(
              attachment: document,
              gateway: gateway,
              downloadFile: (authorize) async {
                await authorize();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('document.$format'), findsOneWidget);
      expect(
        find.byIcon(switch (format) {
          'pdf' => Icons.picture_as_pdf_outlined,
          'xlsx' => Icons.table_chart_outlined,
          _ => Icons.description_outlined,
        }),
        findsOneWidget,
      );
      expect(gateway.downloads, 0);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byTooltip('Download file'));
      await tester.pumpAndSettle();
      expect(gateway.downloads, 1); // One gesture signs and dispatches once.
      expect(find.text('Prepare download'), findsNothing);
    });
  }
  for (final caption in ['', 'Optional caption 😀']) {
    test(
      'type-validated file with caption "$caption" is one typed message',
      () async {
        controller.select(draft());
        await controller.run(chatConversation, caption);
        expect(
          controller.receipt!.attachment!.caption,
          caption.isEmpty ? null : caption,
        );
        expect(gateway.commits, 1);
        expect(gateway.notifications, 1);
        expect(controller.file, isNull);
      },
    );
  }
  test(
    'lost send response retries same identity, one commit and one notification',
    () async {
      gateway.lostReply = true;
      controller.select(draft());
      await controller.run(chatConversation, 'caption');
      final id = controller.reservation!.id,
          request = controller.reservation!.requestId;
      expect(controller.receipt, isNull);
      expect(controller.error, isNotEmpty);
      await controller.run(
        chatConversation,
        'changed caption ignored after reservation',
      );
      expect(controller.receipt!.attachment!.id, id);
      expect(controller.receipt!.attachment!.requestId, request);
      expect(controller.receipt!.attachment!.caption, 'caption');
      expect(gateway.reserves, 1);
      expect(gateway.commits, 1);
      expect(gateway.notifications, 1);
    },
  );
  test('rejected or unavailable content validator never sends', () async {
    controller.select(draft());
    gateway.outage = true;
    await controller.run(chatConversation, '');
    expect(gateway.commits, 0);
    expect(controller.error, isNotEmpty);
    gateway.outage = false;
    gateway.reject = true;
    await controller.run(chatConversation, '');
    expect(gateway.commits, 0);
    expect(controller.phase, 'rejected');
  });
  test('cancel aborts transfer; retry reuses request and acknowledged chunk progress', () async {
    controller.select(draft(length: 300000));
    gateway.onChunk = controller.cancel;
    await controller.run(chatConversation, '');
    expect(gateway.chunks, 1);
    expect(gateway.commits, 0);
    expect(gateway.aborts, greaterThan(0));
    final id = controller.reservation!.id;
    gateway.onChunk = null;
    await controller.run(chatConversation, '');
    expect(controller.progress, 1);
    expect(controller.receipt!.attachment!.id, id);
    expect(gateway.commits, 1);
  });
  test(
    'account switch during upload discards memory and never validates/sends',
    () async {
      controller.select(draft(length: 300000));
      gateway.onChunk = () {
        gateway.actorId = chatOther;
        gateway.changes.add(chatOther);
      };
      await controller.run(chatConversation, '');
      expect(controller.file, isNull);
      expect(controller.reservation, isNull);
      expect(controller.receipt, isNull);
      expect(gateway.commits, 0);
      expect(gateway.row!['state'], 'pending');
    },
  );
  test('server recovery preserves request; no implicit send; pending needs original file', () async {
    controller.select(draft());
    gateway.outage = true;
    await controller.run(chatConversation, 'caption');
    final saved = controller.reservation!;
    controller.clear();
    controller.recover(saved);
    expect(gateway.commits, 0);
    controller.select(ChatAttachmentDraft.select('other.pdf', draft().bytes));
    expect(controller.file, isNull);
    gateway.outage = false;
    controller.select(draft());
    await controller.run(chatConversation, '');
    expect(controller.receipt!.attachment!.requestId, saved.requestId);
    expect(gateway.commits, 1);
  });
  test('strict binding rejects foreign path, mismatched message and invalid caption', () async {
    controller.select(draft());
    await controller.run(chatConversation, '');
    expect(
      () => ChatAttachment.fromRow({
        ...gateway.row!,
        'storage_path': 'other/file',
      }),
      throwsFormatException,
    );
    expect(
      () => ChatMessage.fromRow({
        ...messageRow(3),
        'attachment': gateway.row,
        'caption': null,
      }),
      throwsFormatException,
    );
    expect(
      () => ChatAttachment.fromRow({...gateway.row!, 'caption': '   '}),
      throwsFormatException,
    );
  });
  for (final width in [320.0, 1440.0]) {
    testWidgets('enabled attachment composer and document card at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = ChatFixtureSource(),
          files = ChatAttachmentsController(FakeAttachments());
      final ui = fixtureChatUi(source: source);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ChatPage(
              controller: ui,
              attachments: files,
              conversationId: chatConversation,
              pickAttachment: () async =>
                  XFile.fromData(draft().bytes, name: 'a.pdf', path: 'a.pdf'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(source.accounts.close);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attach file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('a.pdf'), findsOneWidget);
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
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      // Offline type-validated metadata rendering; no real file download.
      controller.select(draft());
      await controller.run(chatConversation, '');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatAttachmentCard(
              attachment: controller.receipt!.attachment!,
              gateway: gateway,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.byTooltip('Download file'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
