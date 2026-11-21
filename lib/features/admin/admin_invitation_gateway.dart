import 'package:supabase_flutter/supabase_flutter.dart';

class AdminInvitationReceipt {
  const AdminInvitationReceipt({
    required this.invitationId,
    required this.expiresAt,
  });

  final String invitationId;
  final DateTime expiresAt;

  factory AdminInvitationReceipt.fromResponse(
    Object? response,
    String expectedId,
  ) {
    if (response is! Map ||
        response['status'] != 'pending' ||
        response['invitationId'] != expectedId ||
        response['expiresAt'] is! String) {
      throw const FormatException('Unexpected invitation response.');
    }
    final expiresAt = DateTime.tryParse(response['expiresAt'] as String);
    if (expiresAt == null) {
      throw const FormatException('Invalid invitation expiry.');
    }
    return AdminInvitationReceipt(
      invitationId: expectedId,
      expiresAt: expiresAt,
    );
  }
}

abstract interface class AdminInvitationGateway {
  Future<AdminInvitationReceipt> sendInvitation({
    required String invitationId,
    required String name,
    required String email,
  });
}

class SupabaseAdminInvitationGateway implements AdminInvitationGateway {
  SupabaseAdminInvitationGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<AdminInvitationReceipt> sendInvitation({
    required String invitationId,
    required String name,
    required String email,
  }) async {
    final response = await _client.functions.invoke(
      'admin-invitations',
      body: {
        'action': 'send_invitation',
        'invitation_id': invitationId,
        'name': name,
        'email': email,
      },
    );
    return AdminInvitationReceipt.fromResponse(response.data, invitationId);
  }
}
