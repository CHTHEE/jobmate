import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_repository.dart';
import '../applications/module2_widgets.dart';
import '../applications/job_details_page.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/phase3_store.dart';
import '../jobs/job_display.dart';

class DemoPlace {
  DemoPlace(this.job);
  final BrowseJob job;
  (double, double) get point => switch (job.id) {
    'demo-job-1' => (1, 1),
    'demo-job-2' => (3, 4),
    _ => (15, -8),
  };
  double get distance => math.sqrt(point.$1 * point.$1 + point.$2 * point.$2);
  String get address =>
      '${job.company}, fictional workplace, ${job.text('location')}';
}

class DemoMap extends StatelessWidget {
  const DemoMap({
    super.key,
    this.places = const [],
    this.height = 360,
    this.radius = 5,
    this.onSelect,
    this.marker,
    this.onMove,
  });
  final List<DemoPlace> places;
  final double radius;
  final double height;
  final ValueChanged<DemoPlace>? onSelect;
  final (double, double)? marker;
  final void Function(double, double)? onMove;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth, height = this.height;
      void move(Offset position) =>
          onMove?.call(position.dx / width, position.dy / height);
      return Semantics(
        label: 'Illustrative demo map. Not geographic imagery or GPS. Markers have accessible buttons.',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTapUp: onMove == null
                ? null
                : (event) => move(event.localPosition),
            onPanUpdate: onMove == null
                ? null
                : (event) => move(event.localPosition),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _GridPainter())),
                  if (marker == null)
                    Positioned(
                      left: width / 2 - math.min(width, height) * .4,
                      top: height / 2 - math.min(width, height) * .4,
                      child: Container(
                        width: math.min(width, height) * .8,
                        height: math.min(width, height) * .8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.teal.withValues(alpha: .12),
                          border: Border.all(color: Colors.teal),
                        ),
                      ),
                    ),
                  if (marker == null)
                    Positioned(
                      left: width / 2 - 12,
                      top: height / 2 - 12,
                      child: const Tooltip(
                        message: 'Fixed demo origin; not your location',
                        child: Icon(Icons.my_location, color: Colors.teal),
                      ),
                    ),
                  for (final p in places)
                    Positioned(
                      left:
                          width / 2 +
                          p.point.$1 / radius * .4 * math.min(width, height) -
                          24,
                      top:
                          height / 2 -
                          p.point.$2 / radius * .4 * math.min(width, height) -
                          24,
                      child: IconButton(
                        tooltip:
                            '${p.job.title} • ${p.distance.toStringAsFixed(1)} demo km',
                        onPressed: () => onSelect?.call(p),
                        icon: const Icon(
                          Icons.location_on,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                  if (marker != null)
                    Positioned(
                      left: width * marker!.$1 - 12,
                      top: height * marker!.$2 - 24,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.teal,
                        size: 32,
                      ),
                    ),
                  const Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Text(
                      'DEMO GRID • not a geographic map',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      marker == null
                          ? 'Fixed sample origin • radius $radius demo km'
                          : 'Tap, drag or use sliders to move the sample marker',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF0ECE0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .06,
          size.height * .08,
          size.width * .22,
          size.height * .24,
        ),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFFD0E4C6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .68,
          size.height * .58,
          size.width * .24,
          size.height * .30,
        ),
        const Radius.circular(16),
      ),
      Paint()..color = const Color(0xFFD0E4C6),
    );
    final river = Path()
      ..moveTo(size.width * .7, 0)
      ..cubicTo(
        size.width * .45,
        size.height * .3,
        size.width * .9,
        size.height * .7,
        size.width * .55,
        size.height,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFB6DCEB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22,
    );
    final lines = Paint()
      ..color = Colors.white
      ..strokeWidth = 16;
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(
        Offset(size.width * i / 6, 0),
        Offset(size.width * i / 6, size.height),
        lines,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 6),
        Offset(size.width, size.height * i / 6),
        lines,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

class NearbyJobsPage extends StatefulWidget {
  const NearbyJobsPage({super.key, this.repository});
  final Module2Repository? repository;
  @override
  State<NearbyJobsPage> createState() => _NearbyJobsPageState();
}

class _NearbyJobsPageState extends State<NearbyJobsPage> {
  late final repo = widget.repository ?? Module2Repository.session;
  final location = TextEditingController();
  String radius = '5', type = '';
  bool map = true;
  @override
  void dispose() {
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final places =
          repo
              .searchJobs(location: location.text, type: type)
              .where((j) => j.text('work_arrangement') != 'remote')
              .map(DemoPlace.new)
              .where((p) => p.distance <= int.parse(radius))
              .toList()
            ..sort((a, b) => a.distance.compareTo(b.distance));
      return DemoPage(
        title: 'Nearby Jobs',
        maxWidth: 768,
        path: AppRoutes.nearbyJobs,
        role: 'job_seeker',
        children: [
          const Phase3Notice(
            'Illustrative map and deterministic sample distances from a fixed demo origin. No GPS, geocoding or map provider is used. Distances are not measurements from your device.',
          ),
          Text(
            'Explore nearby opportunities',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: location,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Filter demo workplace city (no geocoding)',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              ModuleSelect(
                label: 'Demo radius',
                value: radius,
                options: {
                  for (final r in ['2', '5', '10', '25', '50']) r: '$r demo km',
                },
                onChanged: (v) => setState(() => radius = v),
              ),
              ModuleSelect(
                label: 'Job type',
                value: type,
                options: {
                  '': 'All types',
                  for (final j in repo.searchJobs())
                    j.text('employment_type'): jobLabel(
                      j.text('employment_type'),
                    ),
                },
                onChanged: (v) => setState(() => type = v),
              ),
              TextButton(
                onPressed: () => setState(() {
                  location.clear();
                  radius = '5';
                  type = '';
                }),
                child: const Text('Reset filters'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Map'),
                selected: map,
                onSelected: (_) => setState(() => map = true),
              ),
              ChoiceChip(
                label: const Text('List'),
                selected: !map,
                onSelected: (_) => setState(() => map = false),
              ),
              TextButton(
                onPressed: () => demoMessage(
                  context,
                  'Current GPS location is unavailable in this demo. The fixed sample origin remains unchanged.',
                ),
                child: const Text('Current location unavailable (demo)'),
              ),
            ],
          ),
          const Text(
            'Remote roles remain in Browse Jobs; they have no sample workplace distance.',
          ),
          const SizedBox(height: 16),
          if (map)
            DemoMap(
              places: places,
              radius: double.parse(radius),
              onSelect: (p) =>
                  context.push('${AppRoutes.nearbyJobs}/${p.job.id}'),
            ),
          const SizedBox(height: 20),
          Text('${places.length} demo workplaces within $radius sample km'),
          const SizedBox(height: 16),
          if (places.isEmpty)
            const ModuleState(
              title: 'No nearby demo jobs',
              message: 'Try a larger radius or another city/type.',
            ),
          for (final p in places)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: WorkspaceCard(
                title: p.job.title,
                subtitle: p.job.company,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${p.address}\n${p.distance.toStringAsFixed(1)} demo km from the fixed sample origin',
                    ),
                    JobFacts(p.job),
                    if (p.job.unavailable() case final String reason)
                      Text(reason),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () =>
                          context.push('${AppRoutes.nearbyJobs}/${p.job.id}'),
                      child: const Text('View Workplace Details'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class NearbyDetailPage extends StatelessWidget {
  const NearbyDetailPage({super.key, required this.jobId, this.repository});
  final String jobId;
  final Module2Repository? repository;
  @override
  Widget build(BuildContext context) {
    final repo = repository ?? Module2Repository.session;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final j = repo.job(jobId);
        return DemoPage(
          title: 'Workplace Details',
          path: AppRoutes.nearbyJobs,
          role: 'job_seeker',
          back: AppRoutes.nearbyJobs,
          children: [
            const Phase3Notice(
              'All addresses, marker positions and distances are fictional demo context, not geocoded or GPS-derived.',
            ),
            if (j == null ||
                j.text('status') != 'published' ||
                j.text('work_arrangement') == 'remote')
              const ModuleState(
                title: 'Workplace unavailable',
                message: 'This job has no discoverable sample workplace.',
              )
            else ...[
              WorkspaceCard(
                title: j.title,
                subtitle: j.company,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(DemoPlace(j).address),
                    Text(
                      '${DemoPlace(j).distance.toStringAsFixed(1)} demo km • fixed sample origin',
                    ),
                    const SizedBox(height: 16),
                    JobFacts(j),
                    Text(j.text('role_overview')),
                    if (j.unavailable() case final String reason) Text(reason),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () =>
                          context.push('${AppRoutes.browseJobs}/${j.id}'),
                      child: const Text('View Job / Apply'),
                    ),
                    TextButton(
                      onPressed: () => demoMessage(
                        context,
                        'Directions are unavailable until a real map provider and workplace coordinates are integrated.',
                      ),
                      child: const Text('Directions unavailable in demo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              DemoMap(
                height: 180,
                places: [DemoPlace(j)],
                radius: 25,
                onSelect: (_) =>
                    demoMessage(context, 'Sample workplace marker selected.'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class JobLocationDemoPage extends StatefulWidget {
  const JobLocationDemoPage({super.key, this.store});
  final Phase3Store? store;
  @override
  State<JobLocationDemoPage> createState() => _JobLocationDemoPageState();
}

class _JobLocationDemoPageState extends State<JobLocationDemoPage> {
  late final store = widget.store ?? Phase3Store.session;
  late final address = TextEditingController(text: store.locationDraft);
  String? error;
  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => DemoPage(
      title: 'Job Location Picker (demo)',
      path: AppRoutes.jobLocationDemo,
      role: 'employer',
      children: [
        const Phase3Notice(
          'Standalone location UI sandbox. No real job is selected or updated. Coordinates below are demo grid positions, not latitude/longitude. Existing posting location fields remain untouched.',
        ),
        WorkspaceCard(
          title: 'Choose a sample workplace',
          subtitle: 'Address draft and marker position are retained within this demo session.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: address,
                maxLength: 300,
                onChanged: (v) {
                  store.locationDraft = v;
                  if (store.locationConfirmed) {
                    setState(() => store.locationConfirmed = false);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Demo address / search (required)',
                  helperText:
                      'No autocomplete or geocoding provider is connected.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final city in [
                    'Shah Alam',
                    'Kuala Lumpur',
                    'Petaling Jaya',
                  ])
                    ActionChip(
                      label: Text('Sample $city'),
                      onPressed: () {
                        address.text = 'Demo workplace, $city';
                        store.locationDraft = address.text;
                        store.moveMarker(.5, .5);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DemoMap(
                height: 320,
                marker: (store.markerX, store.markerY),
                onMove: store.moveMarker,
              ),
              const SizedBox(height: 16),
              Text(
                'DEMO GRID X: ${(store.markerX * 100).toStringAsFixed(1)} / 100 • Y: ${(store.markerY * 100).toStringAsFixed(1)} / 100',
              ),
              const Text('Latitude: not geocoded • Longitude: not geocoded'),
              Text(
                'Move marker horizontally',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Slider(
                value: store.markerX,
                min: .05,
                max: .95,
                label: 'Demo X ${(store.markerX * 100).round()}',
                onChanged: (v) => store.moveMarker(v, store.markerY),
              ),
              Text(
                'Move marker vertically',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Slider(
                value: store.markerY,
                min: .05,
                max: .95,
                label: 'Demo Y ${(store.markerY * 100).round()}',
                onChanged: (v) => store.moveMarker(store.markerX, v),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: () async {
                  if (address.text.trim().isEmpty) {
                    setState(() => error = 'Enter a demo workplace address.');
                    return;
                  }
                  if (!await demoConfirm(
                    context,
                    'Confirm sample location?',
                    'This location is stored only in the sandbox. It will not change any job posting.',
                  )) {
                    return;
                  }
                  if (!mounted || !context.mounted) return;
                  try {
                    store.confirmLocation(address.text);
                    setState(() => error = null);
                    demoMessage(
                      context,
                      'Demo location confirmed; no posting was changed',
                    );
                  } on StateError catch (e) {
                    setState(() => error = e.message.toString());
                  }
                },
                child: const Text('Confirm Location (demo)'),
              ),
              if (store.locationConfirmed)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Sample confirmed: ${store.locationAddress} • Grid (${(store.markerX * 100).round()}, ${(store.markerY * 100).round()}) • session only',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
