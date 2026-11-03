import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/app_workspace.dart';
import 'dashboard_content.dart';
import '../jobs/job_postings_repository.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/responsive_layout.dart';

enum _HomeMenuAction { profile, company, signOut }

class HomePage extends StatefulWidget {
  final String email;

  const HomePage({super.key, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoadingOut = false;
  bool _canInviteAdmins = false;
  bool _checkingAdminAccess = false;
  bool _canManageAdminPermissions = false;
  String _accountRole = '';
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _company;
  String _memberRole = '';
  bool _loading = true;
  String? _loadError;
  String? _companyError;
  List<Map<String, dynamic>>? _jobPostings;
  String? _jobPostingsError;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess(showMessage: false);
    _loadAccountRole();
  }

  Future<void> _openSection(String path) async {
    if (path == AppRoutes.home) return;
    await context.push<void>(path);
    if (!mounted) return;
    await _loadAccountRole();
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);

    return LoadingOverlay(
      isLoading: _isLoadingOut,
      message: 'Logging out...',
      child: AppWorkspace(
        title: 'Dashboard',
        path: AppRoutes.home,
        role: _accountRole,
        onNavigate: _openSection,
        navigationLocked: _isLoadingOut,
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _isLoadingOut
                ? null
                : () => context.push<void>(AppRoutes.notifications),
            icon: const Icon(Icons.notifications_none_outlined),
          ),
          TextButton(
            onPressed: _isLoadingOut ? null : _handleLogout,
            child: const Text('Log out'),
          ),
        ],
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : WorkspaceContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _loadAccountRole,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ),
                    if (_loadError != null)
                      WorkspaceCard(
                        title: 'Workspace unavailable',
                        child: Column(
                          children: [
                            Text(_loadError!),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: _loadAccountRole,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    else if (_profile != null)
                      DashboardContent(
                        profile: _profile!,
                        email: widget.email,
                        company: _company,
                        companyError: _companyError,
                        memberRole: _memberRole,
                        onProfile: () => _openSection(AppRoutes.profile),
                        onCompany: _openCompanyPage,
                        onVerification: () =>
                            _openSection(AppRoutes.documentSubmission),
                        onRetry: _loadAccountRole,
                        jobPostings: _jobPostings,
                        jobPostingsError: _jobPostingsError,
                      ),
                    const SizedBox(height: 20),
                    WorkspaceCard(
                      title: 'Administrator access',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton(
                            onPressed: _isLoadingOut || _checkingAdminAccess
                                ? null
                                : () => _checkAdminAccess(),
                            child: Text(
                              _checkingAdminAccess
                                  ? 'Checking access...'
                                  : 'Check admin access',
                            ),
                          ),
                          if (_canInviteAdmins) ...[
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _isLoadingOut
                                  ? null
                                  : () async {
                                      await context.push<void>(
                                        AppRoutes.inviteAdmin,
                                      );
                                      if (mounted) {
                                        await _checkAdminAccess(
                                          showMessage: false,
                                        );
                                      }
                                    },
                              child: const Text('Invite administrator'),
                            ),
                            if (_canManageAdminPermissions) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _isLoadingOut
                                    ? null
                                    : () async {
                                        await context.push<void>(
                                          AppRoutes.adminPermissions,
                                        );
                                        if (mounted) {
                                          await _checkAdminAccess(
                                            showMessage: false,
                                          );
                                        }
                                      },
                                child: const Text('Manage admin permissions'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _checkAdminAccess({bool showMessage = true}) async {
    if (_checkingAdminAccess) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;

    setState(() {
      _checkingAdminAccess = true;
      _canInviteAdmins = false;
      _canManageAdminPermissions = false;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'admin-invitations',
        body: {'action': 'check_access'},
      );

      if (!mounted) return;

      if (Supabase.instance.client.auth.currentUser?.id != userId) {
        return;
      }

      final data = response.data;

      if (data is! Map ||
          data['canInviteAdmins'] is! bool ||
          data['canManageAdminPermissions'] is! bool) {
        throw const FormatException('Unexpected access response.');
      }

      setState(() {
        _canInviteAdmins = data['canInviteAdmins'] == true;
        _canManageAdminPermissions = data['canManageAdminPermissions'] == true;
      });

      if (showMessage) {
        _showMessage(data.toString());
      }
    } on FunctionException catch (error) {
      if (!mounted) return;

      final details = error.details;
      final message = details is Map
          ? (details['error'] ?? 'Unable to check access.').toString()
          : 'Request failed (${error.status}).';

      if (showMessage) {
        _showMessage(message);
      }
    } catch (_) {
      if (showMessage) {
        _showMessage('Unable to check administrator access.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _checkingAdminAccess = false;
        });
      }
    }
  }

  Future<void> _loadAccountRole() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _companyError = null;
    });
    try {
      final profile = await client
          .from('users')
          .select(
            'role, name, phone_num, status, verification_status, profile_image_url',
          )
          .eq('user_id', userId)
          .single();
      if (!mounted || client.auth.currentUser?.id != userId) return;
      final role = profile['role'];
      if (role is! String) {
        throw const FormatException('Unexpected account role.');
      }
      Map<String, dynamic>? company;
      String memberRole = '';
      String? companyError;
      if (role == 'employer') {
        try {
          final membership = await client
              .from('company_memberships')
              .select('company_id, member_role')
              .eq('user_id', userId)
              .maybeSingle();
          if (membership != null) {
            memberRole = membership['member_role'] as String? ?? '';
            company = await client
                .from('companies')
                .select(
                  'company_id, company_name, industry, location, verification_status',
                )
                .eq('company_id', membership['company_id'])
                .single();
          }
        } catch (_) {
          companyError = 'Unable to load company information. Retry or open Company profile from navigation.';
        }
      }
      List<Map<String, dynamic>>? postingRecords;
      String? postingError;
      if (role == 'employer') {
        try {
          final repository = JobPostingsRepository(client);
          final access = await repository.loadAccess();
          if (access.allowed) {
            postingRecords = await repository.list(
              access.company!['company_id'].toString(),
            );
          } else {
            postingError = access.message;
          }
        } catch (_) {
          postingError = 'Unable to load company job counts. Refresh or open My Job Postings to retry.';
        }
      }
      if (!mounted || client.auth.currentUser?.id != userId) return;
      setState(() {
        _profile = profile;
        _accountRole = role;
        _company = company;
        _memberRole = memberRole;
        _companyError = companyError;
        _jobPostings = postingRecords;
        _jobPostingsError = postingError;
      });
    } catch (error) {
      debugPrint('Dashboard load failed: $error');
      if (mounted && client.auth.currentUser?.id == userId) {
        setState(
          () => _loadError =
              'Your profile could not be loaded. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCompanyPage() async {
    await context.push<void>(AppRoutes.company);

    if (!mounted) return;

    await _loadAccountRole();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleLogout() async {
    if (_isLoadingOut) return;

    setState(() {
      _isLoadingOut = true;
    });

    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to log out. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOut = false;
        });
      }
    }
  }
}
