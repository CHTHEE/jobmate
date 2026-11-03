import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../applications/module2_widgets.dart';
import '../demo_work/demo_widgets.dart';
import '../demo_work/local_attachment.dart';
import 'phase4_store.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    this.role = 'job_seeker',
    this.store,
    this.loadAccount,
    this.signOut,
  });
  final String role;
  final Phase4Store? store;
  final Future<Map<String, dynamic>> Function()? loadAccount;
  final Future<void> Function()? signOut;
  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late final store = widget.store ?? Phase4Store.session;
  late Future<Map<String, dynamic>> account = load();
  bool busy = false;
  String? error;
  String get path => widget.role == 'employer'
      ? AppRoutes.employerSettings
      : widget.role == 'administrator'
      ? AppRoutes.adminSettings
      : AppRoutes.settings;
  Future<Map<String, dynamic>> load() async {
    if (widget.loadAccount != null) return widget.loadAccount!();
    final client = Supabase.instance.client,
        id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in to view account settings.');
    final profile = await client
        .from('users')
        .select('name, phone_num, profile_image_url, role, status')
        .eq('user_id', id)
        .single();
    if (client.auth.currentUser?.id != id ||
        profile['role'] != widget.role ||
        profile['status'] != 'active') {
      throw StateError('The signed-in account is unavailable for this page.');
    }
    return {...profile, 'email': client.auth.currentUser?.email ?? ''};
  }

  Future<void> logout() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of your real account?'),
        content: const Text(
          'This ends the local Supabase session. Demo state will reset; your server data is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.signOut != null) {
        await widget.signOut!();
      } else {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (mounted) context.go(AppRoutes.home);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not sign out. Retry; your account has not been deleted.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: 'Account Settings',
    path: path,
    role: widget.role,
    navigationLocked: busy,
    child: WorkspaceContent(
      child: FutureBuilder<Map<String, dynamic>>(
        future: account,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return ModuleState(
              title: 'Account settings unavailable',
              message: 'Could not load your real account details. Retry or use the workspace navigation.',
              action: () => setState(() {
                account = load();
              }),
            );
          }
          final data = snapshot.data!,
              completed = [
                data['name'],
                data['email'],
                data['phone_num'],
                data['profile_image_url'],
              ].where((v) => '$v'.trim().isNotEmpty && v != null).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkspaceCard(
                title: 'Your real account',
                subtitle: 'This summary comes from your existing account. Sample preferences below are explicitly separate.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorkspaceInfo('Name', '${data['name'] ?? ''}'),
                    WorkspaceInfo('Email', '${data['email'] ?? ''}'),
                    WorkspaceInfo('Role', workspaceLabel(widget.role)),
                    Text('Profile completion: ${completed * 25}%'),
                    LinearProgressIndicator(value: completed / 4),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => context.push(AppRoutes.profile),
                      child: const Text('Personal information / Edit profile'),
                    ),
                    if (widget.role == 'employer')
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => context.push(AppRoutes.company),
                        child: const Text('Company profile / Verification'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              WorkspaceCard(
                title: 'Password & security',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'The existing email verification and password-change flow remains in use.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => context.push(AppRoutes.verifyPassword),
                      child: const Text('Change Password (real account)'),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Two-factor authentication'),
                      subtitle: Text(
                        'Not connected. No security setting is changed.',
                      ),
                      trailing: Icon(Icons.lock_outline),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => context.push(AppRoutes.privacy),
                      child: const Text('Privacy policy'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => context.push(AppRoutes.terms),
                      child: const Text('Terms of service'),
                    ),
                  ],
                ),
              ),
              if (widget.role != 'administrator') ...[
                const SizedBox(height: 20),
                WorkspaceCard(
                  title: 'Notification preferences • DEMO',
                  subtitle: 'These switches are local previews only. They do not enable notifications or change delivery settings.',
                  child: Column(
                    children: [
                      for (final item in [
                        'Application updates',
                        'Messages',
                        'Email notifications',
                        'SMS notifications',
                      ])
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item),
                          value:
                              store.notifications['${widget.role}:$item'] ??
                              false,
                          onChanged: busy
                              ? null
                              : (v) => setState(
                                  () =>
                                      store.notifications['${widget.role}:$item'] =
                                          v,
                                ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                WorkspaceCard(
                  title: 'Additional profile presentation',
                  subtitle: 'Prototype-only bio/skills/categories/resume or company presentation fields are available in a separate fictional preview; no real profile is overwritten.',
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => context.push(
                            widget.role == 'employer'
                                ? AppRoutes.companyPreview
                                : AppRoutes.profilePreview,
                          ),
                    child: Text(
                      widget.role == 'employer'
                          ? 'Edit Sample Company (demo)'
                          : 'Edit Sample Profile (demo)',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              WorkspaceCard(
                title: 'Account actions',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    OutlinedButton(
                      onPressed: busy ? null : logout,
                      child: Text(
                        busy ? 'Signing out…' : 'Sign out (real account)',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => moduleModal<void>(
                              context,
                              ModalBody(
                                title: 'Delete account',
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  const FilledButton(
                                    onPressed: null,
                                    child: Text('Delete account unavailable'),
                                  ),
                                ],
                                children: [
                                  const Text(
                                    'Account deletion is not connected. Deletion would be permanent and needs identity checks, ownership handling and retention rules. No account or data will be deleted from this preview.',
                                  ),
                                ],
                              ),
                            ),
                      child: const Text('Account deletion information'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class ExtendedProfilePage extends StatefulWidget {
  const ExtendedProfilePage({super.key, this.employer = false, this.store});
  final bool employer;
  final Phase4Store? store;
  @override
  State<ExtendedProfilePage> createState() => _ExtendedProfilePageState();
}

class _ExtendedProfilePageState extends State<ExtendedProfilePage> {
  late final store = widget.store ?? Phase4Store.session;
  String get role => widget.employer ? 'employer' : 'job_seeker';
  late final draft = store.profile(role);
  late final name = TextEditingController(text: draft.name),
      bio = TextEditingController(text: draft.bio),
      location = TextEditingController(text: draft.location),
      skills = TextEditingController(text: draft.skills),
      industry = TextEditingController(text: draft.industry),
      size = TextEditingController(text: draft.size),
      contact = TextEditingController(text: draft.contact),
      website = TextEditingController(text: draft.website);
  String? error;
  bool reading = false, saved = false;
  @override
  void dispose() {
    for (final controller in [
      name,
      bio,
      location,
      skills,
      industry,
      size,
      contact,
      website,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> resume() async {
    final generation = store.generation;
    setState(() {
      reading = true;
      error = null;
    });
    try {
      final files = await pickDemoFiles();
      if (!mounted || generation != store.generation) return;
      if (files.isEmpty) return;
      if (files.length != 1 || files.single.kind != 'application/pdf') {
        throw const FormatException('Choose one PDF resume, at most 5 MiB.');
      }
      setState(() => draft.resume = files.single);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not read the local resume. Retry; the draft is preserved.',
        );
      }
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => DemoPage(
    title: widget.employer ? 'Edit Sample Company' : 'Edit Sample Profile',
    path: widget.employer ? AppRoutes.employerSettings : AppRoutes.settings,
    role: role,
    back: widget.employer ? AppRoutes.employerSettings : AppRoutes.settings,
    children: [
      const Phase3Notice(
        'Fictional extended profile UI only. This page never changes real names, photos, verification, company membership or existing profile data. Use the existing Personal Profile / Company Profile pages for supported real edits.',
      ),
      WorkspaceCard(
        title: widget.employer
            ? 'Company presentation preview'
            : 'Job Seeker presentation preview',
        subtitle: 'Draft fields and selected local files survive in-app navigation for this session.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: name,
              maxLength: 100,
              onChanged: (v) => draft.name = v,
              decoration: InputDecoration(
                labelText: widget.employer
                    ? 'Sample company name'
                    : 'Sample display name',
              ),
            ),
            TextField(
              controller: bio,
              maxLength: 250,
              minLines: 3,
              maxLines: 5,
              onChanged: (v) => draft.bio = v,
              decoration: InputDecoration(
                labelText: widget.employer
                    ? 'Sample company description'
                    : 'Bio (maximum 250 characters)',
              ),
            ),
            TextField(
              controller: location,
              maxLength: 150,
              onChanged: (v) => draft.location = v,
              decoration: const InputDecoration(
                labelText: 'Location (sample text)',
              ),
            ),
            if (widget.employer) ...[
              TextField(
                controller: industry,
                maxLength: 100,
                onChanged: (v) => draft.industry = v,
                decoration: const InputDecoration(
                  labelText: 'Industry (sample)',
                ),
              ),
              TextField(
                controller: size,
                maxLength: 50,
                onChanged: (v) => draft.size = v,
                decoration: const InputDecoration(
                  labelText: 'Company size (sample)',
                ),
              ),
              TextField(
                controller: contact,
                maxLength: 150,
                onChanged: (v) => draft.contact = v,
                decoration: const InputDecoration(
                  labelText: 'Contact name/details (sample)',
                ),
              ),
              TextField(
                controller: website,
                maxLength: 200,
                onChanged: (v) => draft.website = v,
                decoration: const InputDecoration(
                  labelText: 'Website (optional, https://...)',
                ),
              ),
              const Text(
                'Company verification: not connected in this sample. No approval or verified badge can be set here.',
              ),
            ] else ...[
              const SizedBox(height: 16),
              ModuleSelect(
                label: 'Availability (demo)',
                value: draft.availability,
                options: const {
                  'Available': 'Available',
                  'Part-time only': 'Part-time only',
                  'Unavailable': 'Unavailable',
                },
                onChanged: (v) => setState(() => draft.availability = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: skills,
                maxLength: 200,
                onChanged: (v) => draft.skills = v,
                decoration: const InputDecoration(
                  labelText: 'Skills (comma-separated, up to 10)',
                ),
              ),
              Text('Job categories: ${draft.categories.length} / 5'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in [
                    'Retail',
                    'Hospitality',
                    'Events',
                    'Technology',
                    'Administration',
                    'Logistics',
                    'Design',
                  ])
                    FilterChip(
                      label: Text(c),
                      selected: draft.categories.contains(c),
                      onSelected: (v) {
                        if (v && draft.categories.length >= 5) {
                          demoMessage(context, 'Choose up to five categories.');
                          return;
                        }
                        setState(() {
                          if (v) {
                            draft.categories.add(c);
                          } else {
                            draft.categories.remove(c);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: reading ? null : resume,
                child: Text(
                  reading
                      ? 'Reading local resume…'
                      : 'Choose sample PDF resume (local only)',
                ),
              ),
              if (reading) const LinearProgressIndicator(),
              if (draft.resume != null)
                AttachmentTile(
                  draft.resume!,
                  onRemove: reading
                      ? null
                      : () => setState(() => draft.resume = null),
                )
              else
                const Text(
                  'No resume selected. Nothing is uploaded or shared.',
                ),
            ],
            const SizedBox(height: 20),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (saved)
              const Text(
                'Sample preview saved in this session only. Your real account/company is unchanged.',
              ),
            FilledButton(
              onPressed: reading
                  ? null
                  : () {
                      final uri = Uri.tryParse(draft.website);
                      if (draft.name.trim().isEmpty) {
                        setState(
                          () => error = 'Enter a sample display/company name.',
                        );
                        return;
                      }
                      if (!widget.employer &&
                          draft.skills
                                  .split(',')
                                  .where((s) => s.trim().isNotEmpty)
                                  .length >
                              10) {
                        setState(() => error = 'Enter up to ten skills.');
                        return;
                      }
                      if (widget.employer &&
                          draft.website.isNotEmpty &&
                          (uri == null ||
                              !['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty)) {
                        setState(
                          () => error = 'Enter a valid http/https website URL.',
                        );
                        return;
                      }
                      setState(() {
                        saved = true;
                        error = null;
                      });
                    },
              child: const Text('Save Sample Preview (demo)'),
            ),
            OutlinedButton(
              onPressed: reading
                  ? null
                  : () => context.push(
                      widget.employer ? AppRoutes.company : AppRoutes.profile,
                    ),
              child: Text(
                widget.employer
                    ? 'Open real Company Profile'
                    : 'Open real Personal Profile',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
