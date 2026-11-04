import 'package:flutter/material.dart';

import 'module2_repository.dart';

/// Keeps the existing avatar footprint while private logos load or fail.
class PublishedCompanyLogo extends StatelessWidget {
  const PublishedCompanyLogo({
    super.key,
    required this.job,
    required this.repository,
    this.size = 40,
    this.fallback,
  });
  final BrowseJob job;
  final PublishedJobsRepository repository;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder =
        fallback ??
        CircleAvatar(
          radius: size / 2,
          child: Text(job.company.isEmpty ? '?' : job.company.characters.first),
        );
    return SizedBox.square(
      dimension: size,
      child: ListenableBuilder(
        listenable: repository,
        builder: (context, _) => FutureBuilder<String?>(
          future: repository.logoUrl(job.logoStoragePath),
          builder: (context, snapshot) {
            final url = snapshot.connectionState == ConnectionState.done
                ? snapshot.data
                : null;
            if (url == null) return placeholder;
            return ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.contain,
                semanticLabel: '${job.company} logo',
                frameBuilder: (_, child, frame, _) {
                  if (frame != null) {
                    debugPublishedLogo('Image frame decoded successfully');
                  }
                  return child;
                },
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
                errorBuilder: (_, failure, _) {
                  debugPublishedLogo(
                    failure is NetworkImageLoadException
                        ? 'Image load failed HTTP status=${failure.statusCode}'
                        : 'Image rendering failed type=${failure.runtimeType}',
                  );
                  return placeholder;
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
