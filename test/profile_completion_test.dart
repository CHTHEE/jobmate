import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobmate/features/home/dashboard_content.dart';

void main() {
  for (final role in ['job_seeker', 'employer']) {
    testWidgets('$role hides completed profile reminder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardContent(
                profile: {
                  'role': role,
                  'name': 'Test User',
                  'phone_num': '0123456789',
                  'profile_image_url': 'https://example.com/photo.jpg',
                  'status': 'active',
                },
                email: 'test@example.com',
                onProfile: () {},
                onCompany: () {},
                onVerification: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Complete your profile'), findsNothing);
      expect(find.textContaining('Profile completion:'), findsNothing);
    });
  }
}
