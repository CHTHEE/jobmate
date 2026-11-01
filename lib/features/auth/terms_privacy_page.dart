import 'package:flutter/material.dart';

import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';

enum PolicySection {
  terms,
  privacy,
}

class TermsAndPrivacyPage extends StatelessWidget {
  final PolicySection initialSection;

  const TermsAndPrivacyPage({
    super.key,
    required this.initialSection,
  });

  @override
  Widget build(BuildContext context) {
    final title = initialSection == PolicySection.terms
        ? 'Terms of Service'
        : 'Privacy Policy';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: mobileBackLeading(context),
        title: Text(title),
      ),
      body: SafeArea(
        child: ResponsiveContent(
          maxWidth: 760,
            child: ListView(
              padding: ResponsiveLayout.pagePadding(context),
              children: [
                const Text(
                  'JobMate General Policy',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Draft version 0.1'),
                const SizedBox(height: 24),
                SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section(
                        'Terms of Service',
                        const [
                          'Users must provide accurate account and Company information.',
                          'Users are responsible for protecting their passwords and account access.',
                          'Employer accounts must submit valid Company supporting documents before Company verification.',
                          'A Company Owner cannot transfer ownership to another account.',
                          'Users must not upload harmful, false, illegal, or misleading content.',
                          'JobMate may limit access when an account violates platform rules.',
                        ],
                      ),
                      const SizedBox(height: 20),
                      _section(
                        'Privacy Policy',
                        const [
                          'JobMate stores account details such as name, email, role, and optional profile information.',
                          'Company documents are stored privately and are accessible only to authorized reviewers and permitted Company users.',
                          'JobMate uses submitted Company information for verification and platform operations.',
                          'Users may update permitted profile information through the application.',
                          'Users should contact the platform administrator if they need help with their account or data.',
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }

  Widget _section(String title, List<String> points) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('• $point'),
              ),
          ],
        ),
      ),
    );
  }
}
