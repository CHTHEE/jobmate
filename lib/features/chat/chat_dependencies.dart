import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_realtime.dart';
import 'chat_repository.dart';
import 'chat_ui_controller.dart';
import 'chat_pending_store.dart';
import 'chat_source.dart';
import 'chat_attachment_models.dart';

// Stores serialize I/O across page instances, but cache no account rows. Auth
// changes still clear every repository/controller; disk keys remain owner-scoped.
final _pendingStores = <String, LocalChatPendingStore>{};
LocalChatPendingStore sharedChatPendingStore(String projectUrl) =>
    _pendingStores.putIfAbsent(
      Uri.parse(projectUrl).origin,
      () => LocalChatPendingStore(
        storage: SharedPreferencesGotrueAsyncStorage(),
        projectUrl: projectUrl,
      ),
    );

ChatRepository authenticatedChatRepository() => ChatRepository(
  source: SupabaseChatSource(
    Supabase.instance.client,
    attachmentsEnabled: chatAttachmentsEnabled,
  ),
  pendingStore: sharedChatPendingStore(dotenv.env['SUPABASE_URL']!),
);
ChatUiController authenticatedChatUi() => ChatUiController(
  repository: authenticatedChatRepository(),
  realtime: SupabaseChatRealtime(Supabase.instance.client),
);
