import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Use the same authenticated private-bucket download as Company profile.
Future<Uint8List?> loadCompanyLogo(SupabaseClient client, String? path) async {
  if (path == null || path.isEmpty) return null;
  return client.storage.from('jobmate-company-logos').download(path);
}

class CompanyIdentity extends StatelessWidget {
  const CompanyIdentity({super.key, required this.name, this.logo});
  final String name;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (logo != null)
        Image.memory(
          logo!,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          semanticLabel: '$name logo',
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      Text(name, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}
