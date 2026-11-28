import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../payments/payment_feature_gate.dart';
import '../payments/payment_recipient_settings.dart';
import '../payments/payment_simulation_gateway.dart';
import '../phase4/phase4_store.dart';
import '../phase4/reputation_page.dart';
import '../trust/job_seeker_trust_score.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'job_seeker_profile_sections.dart';
import 'employer_profile_sections.dart';

enum MyAccountSection { profile, reputation, payment, security, notifications }

MyAccountSection myAccountSectionFromName(String? value) => switch (value) {
  'reputation' => MyAccountSection.reputation,
  'payment' => MyAccountSection.payment,
  'security' => MyAccountSection.security,
  'notifications' => MyAccountSection.notifications,
  _ => MyAccountSection.profile,
};

List<MyAccountSection> myAccountSectionsForRole(
  String role, {
  bool paymentDetailsEnabled = paymentRecipientSimulationEnabled,
}) => [
  MyAccountSection.profile,
  if (role == 'job_seeker') MyAccountSection.reputation,
  if (role == 'job_seeker' && paymentDetailsEnabled) MyAccountSection.payment,
  MyAccountSection.security,
  MyAccountSection.notifications,
];

extension on MyAccountSection {
  String get label => switch (this) {
    MyAccountSection.profile => 'Personal profile',
    MyAccountSection.reputation => 'Reputation',
    MyAccountSection.payment => 'Payment details',
    MyAccountSection.security => 'Account & security',
    MyAccountSection.notifications => 'Notifications',
  };

  IconData get icon => switch (this) {
    MyAccountSection.profile => Icons.person_outline,
    MyAccountSection.reputation => Icons.insights_outlined,
    MyAccountSection.payment => Icons.account_balance_wallet_outlined,
    MyAccountSection.security => Icons.lock_outline,
    MyAccountSection.notifications => Icons.notifications_outlined,
  };
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.initialSection = MyAccountSection.profile,
  });

  final MyAccountSection initialSection;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;
  late final _paymentGateway = SupabasePaymentSimulationGateway(_supabase);
  final _settingsStore = Phase4Store.session;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isSigningOut = false;
  bool _confirmingExit = false;
  late MyAccountSection _selectedSection = widget.initialSection;
  int _reputationRefreshToken = 0;
  late bool _reputationHasBeenOpened =
      widget.initialSection == MyAccountSection.reputation;

  String _savedName = '';
  String _savedPhone = '';
  String? _loadError;
  String _email = '';
  String _accountStatus = '';
  String _role = '';
  String _verificationStatus = '';
  String? _avatarUrl;

  DateTime? _createdAt;
  DateTime? _updatedAt;

  bool get _isBusy => _isLoading || _isSaving || _isUploading || _isSigningOut;
  bool _isUploading = false;

  bool get _canEdit => !_isBusy && _accountStatus == 'active';

  bool get _hasUnsavedPersonalChanges =>
      _isEditing &&
      (_nameController.text.trim() != _savedName ||
          _phoneController.text.trim() != _savedPhone);

  List<MyAccountSection> get _sections => myAccountSectionsForRole(_role);

  static const _profileColumns =
      'name, phone_num, status, role, verification_status,'
      'profile_image_url, created_at, updated_at';

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onPersonalDraftChanged);
    _phoneController.addListener(_onPersonalDraftChanged);
    _loadProfile();
  }

  void _onPersonalDraftChanged() {
    if (mounted && _isEditing) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw StateError("No signed-in user.");
      }

      final profile = await _supabase
          .from('users')
          .select(_profileColumns)
          .eq('user_id', user.id)
          .single();

      if (!mounted) return;

      _nameController.text = (profile['name'] as String?) ?? '';
      _phoneController.text = (profile['phone_num'] as String?) ?? '';

      setState(() {
        _savedName = _nameController.text;
        _savedPhone = _phoneController.text;
        _isEditing = false;
        _email = user.email ?? '';
        _accountStatus = (profile['status'] as String?) ?? '';
        _role = (profile['role'] as String?) ?? '';
        _verificationStatus = (profile['verification_status'] as String?) ?? '';
        _avatarUrl = (profile['profile_image_url'] as String?) ?? '';
        _createdAt = DateTime.tryParse(
          (profile['created_at'] as String?) ?? '',
        );
        _updatedAt = DateTime.tryParse(
          (profile['updated_at'] as String?) ?? '',
        );
      });
    } catch (error) {
      debugPrint('Profile load failed: $error');

      if (!mounted) return;

      setState(() {
        _loadError = 'Unable to load your profile. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_canEdit || !_isEditing) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || name.runes.length > 100) {
      _showMessage('Full name must contain 1 to 100 characters.');
      return;
    }

    if (phone.runes.length > 20) {
      _showMessage('Phone number must not exceed 20 characters.');
      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      _showMessage('Please log in again.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final saved = await _supabase
          .from('users')
          .update({'name': name, 'phone_num': phone.isEmpty ? null : phone})
          .eq('user_id', user.id)
          .select('name, phone_num, updated_at')
          .single();

      if (!mounted) return;

      _nameController.text = (saved['name'] as String?) ?? '';
      _phoneController.text = (saved['phone_num'] as String?) ?? '';

      setState(() {
        _savedName = _nameController.text;
        _savedPhone = _phoneController.text;
        _updatedAt = DateTime.tryParse((saved['updated_at'] as String?) ?? '');
        _isEditing = false;
      });

      _showMessage('Profile saved.');
    } on PostgrestException catch (error) {
      debugPrint(
        'Profile save failed (${error.code}): '
        '${error.message}',
      );

      _showMessage('Unable to save your profile. Please try again.');
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _displayLabel(String value) {
    const labels = {
      'job_seeker': 'Job Seeker',
      'employer': 'Employer',
      'administrator': 'Administrator',
      'active': 'Active',
      'suspended': 'Suspended',
      'deactivated': 'Deactivated',
      'not_submitted': 'Not submitted',
      'pending': 'Pending review',
      'verified': 'Verified',
      'rejected': 'Rejected',
    };
    return labels[value] ?? 'Unknown';
  }

  Widget _infoRow(String title, String value) => WorkspaceInfo(title, value);

  String _formatDate(DateTime? value) {
    if (value == null) return 'Not available';

    final local = value.toLocal();
    final formatter = MaterialLocalizations.of(context);

    final date = formatter.formatMediumDate(local);

    final time = formatter.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );

    return '$date, $time';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAvatar() async {
    if (!_canEdit) return;

    final user = _supabase.auth.currentUser;

    if (user == null) {
      _showMessage('Please log in again.');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Alternative on supported devices:
        // source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
        requestFullMetadata: false,
      );

      if (image == null || !mounted) return;

      if (await image.length() > 2 * 1024 * 1024) {
        _showMessage('Please choose an image below 2 MiB.');
        return;
      }

      final bytes = await image.readAsBytes();

      final mimeType = lookupMimeType(image.name, headerBytes: bytes);

      const extensions = {
        'image/jpeg': 'jpg',
        'image/png': 'png',
        'image/webp': 'webp',
      };

      final extension = extensions[mimeType];

      if (extension == null) {
        _showMessage('Please choose a JPG, PNG or WebP image.');
        return;
      }

      if (_supabase.auth.currentUser?.id != user.id) {
        _showMessage('Your login has changed. Please reopen this page.');
        return;
      }

      final path =
          '${user.id}/'
          '${DateTime.now().microsecondsSinceEpoch}.$extension';

      await _supabase.storage
          .from('jobmate-avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
              // upsert: true overwrites an existing path.
              // It requires additional SELECT / UPDATE policies.
            ),
          );

      final url = _supabase.storage.from('jobmate-avatars').getPublicUrl(path);

      final saved = await _supabase
          .from('users')
          .update({'profile_image_url': url})
          .eq('user_id', user.id)
          .select('profile_image_url, updated_at')
          .single();

      if (!mounted) return;

      setState(() {
        _avatarUrl = saved['profile_image_url'] as String?;

        _updatedAt = DateTime.tryParse((saved['updated_at'] as String?) ?? '');
      });

      _showMessage('Profile photo updated.');
    } catch (error) {
      debugPrint('Avatar update failed: $error');

      _showMessage('Unable to update your photo. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Widget _buildProfileHeader() {
    final avatarUrl = _avatarUrl;
    const accent = Color(0xFF40577D);
    const accentSoft = Color(0xFFEAF0F8);

    return Column(
      children: [
        SizedBox(
          height: 146,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(
                        Icons.badge_outlined,
                        color: Colors.white54,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 42,
                left: 0,
                right: 0,
                child: Center(
                  child: Tooltip(
                    message: _canEdit
                        ? 'Change profile photo'
                        : 'Profile photo',
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x220F172A),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: avatarUrl == null || avatarUrl.isEmpty
                                  ? Container(
                                      color: accentSoft,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.person_outline,
                                        color: accent,
                                        size: 48,
                                      ),
                                    )
                                  : Image.network(
                                      avatarUrl,
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: accentSoft,
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.person_outline,
                                                  color: accent,
                                                  size: 48,
                                                ),
                                              ),
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 1,
                            bottom: 1,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _canEdit
                                    ? accent
                                    : const Color(0xFF718096),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _canEdit ? _pickAvatar : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          _savedName.isEmpty ? 'Personal profile' : _savedName,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          _email,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _profileBadge(Icons.badge_outlined, _displayLabel(_role)),
            _profileBadge(Icons.circle, _displayLabel(_accountStatus)),
            if (_role != 'job_seeker')
              _profileBadge(
                _verificationStatus == 'verified'
                    ? Icons.verified_outlined
                    : Icons.pending_outlined,
                _displayLabel(_verificationStatus),
              ),
          ],
        ),
        if (_createdAt != null) ...[
          const SizedBox(height: 12),
          Text(
            'Member since ${MaterialLocalizations.of(context).formatMediumDate(_createdAt!.toLocal())}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ],
    );
  }

  Widget _profileBadge(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF0F8),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD7E0EE)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF40577D)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ],
    ),
  );

  void _startEditing() {
    if (!_canEdit) return;

    _nameController.text = _savedName;
    _phoneController.text = _savedPhone;

    setState(() {
      _isEditing = true;
    });
  }

  void _cancelEditing() {
    if (_isBusy) return;

    FocusScope.of(context).unfocus();

    _nameController.text = _savedName;
    _phoneController.text = _savedPhone;

    setState(() {
      _isEditing = false;
    });
  }

  void _openPasswordVerification() {
    if (!_canEdit) return;

    final hasUnsavedChanges =
        _nameController.text.trim() != _savedName ||
        _phoneController.text.trim() != _savedPhone;

    if (hasUnsavedChanges) {
      _showMessage('Save or cancel your profile changes first.');
      return;
    }

    context.push<void>(AppRoutes.verifyPassword);
  }

  Widget _buildPersonalDetails() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.contact_page_outlined,
              color: Color(0xFF40577D),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personal details',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Your contact information',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),

            if (!_isEditing)
              IconButton(
                tooltip: 'Edit personal details',
                onPressed: _canEdit ? _startEditing : null,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),

        const Divider(height: 28),
        _infoRow('Email address', _email),
        const Divider(height: 1),

        if (_isEditing) ...[
          TextField(
            controller: _nameController,
            enabled: _canEdit,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: 100,
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _phoneController,
            enabled: _canEdit,
            decoration: const InputDecoration(
              labelText: 'Phone Number (optional)',
              hintText: '+60123456789',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 20,
          ),

          const SizedBox(height: 20),

          ResponsiveGrid(
            minItemWidth: 200,
            maxColumns: 2,
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _isBusy ? null : _cancelEditing,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _canEdit ? _saveProfile : null,
                child: const Text('Save Changes'),
              ),
            ],
          ),

          const SizedBox(height: 12),
        ] else ...[
          _infoRow(
            'Full name',
            _savedName.isEmpty ? 'Not provided' : _savedName,
          ),
          const Divider(height: 1),
          _infoRow(
            'Phone number',
            _savedPhone.isEmpty ? 'Not provided' : _savedPhone,
          ),
        ],

        if (_accountStatus != 'active')
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Your account currently cannot edit '
              'profile details.',
            ),
          ),
      ],
    );
  }

  Future<void> _openDocumentSubmission() async {
    if (!_canEdit) return;

    final hasUnsavedChanges =
        _nameController.text.trim() != _savedName ||
        _phoneController.text.trim() != _savedPhone;

    if (_isEditing && hasUnsavedChanges) {
      _showMessage('Save or cancel your profile changes first.');
      return;
    }

    await context.push<void>(AppRoutes.documentSubmission);

    if (!mounted) return;

    // 回到 Profile 后，重新读取最新的 verification_status。
    await _loadProfile();
  }

  Future<void> _signOut() async {
    if (_isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          _hasUnsavedPersonalChanges
              ? 'Your unsaved personal details will be discarded when you sign out.'
              : 'You will need to sign in again to access JobMate.',
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
    setState(() => _isSigningOut = true);
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
      if (mounted) context.go(AppRoutes.home);
    } catch (_) {
      _showMessage('Unable to sign out. Please try again.');
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<void> _leaveAccount() async {
    if (_isBusy || _confirmingExit) return;
    _confirmingExit = true;
    final leave = await confirmDiscardChanges(
      context,
      _hasUnsavedPersonalChanges,
    );
    _confirmingExit = false;
    if (!leave || !mounted) return;
    _nameController.text = _savedName;
    _phoneController.text = _savedPhone;
    setState(() => _isEditing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) returnToPage(context, AppRoutes.home);
    });
  }

  void _selectSection(MyAccountSection section) {
    if (_sections.contains(section) && section != _selectedSection) {
      setState(() {
        _selectedSection = section;
        if (section == MyAccountSection.reputation) {
          if (_reputationHasBeenOpened) {
            _reputationRefreshToken++;
          } else {
            _reputationHasBeenOpened = true;
          }
        }
      });
    }
  }

  Widget _buildProfileSection([Widget? reputation]) {
    final details = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildPersonalDetails(),
      ),
    );
    final sections = <Widget>[
      if (reputation != null) ...[reputation, const SizedBox(height: 16)],
      details,
    ];
    if (_role == 'job_seeker') {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        sections.addAll([
          const SizedBox(height: 20),
          JobSeekerProfileSections(userId: userId, canEdit: _canEdit),
        ]);
      }
    }
    if (_role == 'employer') {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        sections.addAll([
          const SizedBox(height: 20),
          EmployerProfileSections(userId: userId, canEdit: _canEdit),
        ]);
      }
    }
    if (_role == 'job_seeker' || _role == 'employer') {
      sections.addAll([
        const SizedBox(height: 20),
        WorkspaceCard(
          title: _role == 'job_seeker' ? 'My Resume' : 'Personal verification',
          subtitle: _role == 'job_seeker'
              ? 'Upload or replace your resume anytime. No administrator approval is required.'
              : 'Personal documents and history are separate from company verification.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_role != 'job_seeker')
                Align(
                  alignment: Alignment.centerLeft,
                  child: WorkspaceStatus(_verificationStatus),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _canEdit ? _openDocumentSubmission : null,
                icon: const Icon(Icons.folder_outlined),
                label: Text(
                  _role == 'job_seeker'
                      ? 'Manage resume'
                      : 'Documents & submission history',
                ),
              ),
            ],
          ),
        ),
      ]);
    }
    if (_role == 'employer') {
      sections.addAll([
        const SizedBox(height: 20),
        WorkspaceCard(
          title: 'Company profile',
          subtitle: 'View your company details, membership and company verification on the Company page.',
          child: OutlinedButton.icon(
            onPressed: _canEdit && !_isEditing
                ? () => context.push<void>(AppRoutes.company)
                : null,
            icon: const Icon(Icons.business_outlined),
            label: const Text('Open company profile'),
          ),
        ),
      ]);
    }
    if (_role == 'job_seeker' && jobSeekerTrustScoreEnabled) {
      sections.addAll([
        const SizedBox(height: 20),
        JobSeekerTrustScoreSection(
          isActiveJobSeeker: _accountStatus == 'active',
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  Widget _buildSecuritySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkspaceCard(
        title: 'Account & security',
        subtitle: 'Your sign-in details and account status.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoRow('Email address', _email),
            _infoRow('Account status', _displayLabel(_accountStatus)),
            _infoRow('Created', _formatDate(_createdAt)),
            _infoRow('Last updated', _formatDate(_updatedAt)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _canEdit ? _openPasswordVerification : null,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Change password'),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => context.push<void>(AppRoutes.privacy),
                  child: const Text('Privacy policy'),
                ),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => context.push<void>(AppRoutes.terms),
                  child: const Text('Terms of service'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      WorkspaceCard(
        title: 'Account actions',
        child: OutlinedButton.icon(
          onPressed: _isBusy ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: Text(_isSigningOut ? 'Signing out…' : 'Sign out'),
        ),
      ),
    ],
  );

  Widget _buildNotificationsSection() => WorkspaceCard(
    title: 'Notification preferences',
    subtitle: 'These local preferences do not change server delivery settings.',
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
            value: _settingsStore.notifications['$_role:$item'] ?? false,
            onChanged: _isBusy
                ? null
                : (value) => setState(
                    () => _settingsStore.notifications['$_role:$item'] = value,
                  ),
          ),
      ],
    ),
  );

  Widget _buildSectionContent() {
    if (_role == 'job_seeker') {
      return ReputationContent(
        interactive: !_isEditing && !_isBusy,
        refreshToken: _reputationRefreshToken,
        onViewFull: () => _selectSection(MyAccountSection.reputation),
        workerLayout: (compact, full) => _buildSectionStack(compact, full),
      );
    }
    return _buildSectionStack(null, null);
  }

  Widget _buildSectionStack(Widget? compact, Widget? full) {
    final sections = _sections;
    final selectedSection = sections.contains(_selectedSection)
        ? _selectedSection
        : MyAccountSection.profile;
    return IndexedStack(
      index: sections.indexOf(selectedSection),
      children: [
        for (final section in sections)
          KeyedSubtree(
            key: ValueKey('my-account-section-${section.name}'),
            child: switch (section) {
              MyAccountSection.profile => _buildProfileSection(compact),
              MyAccountSection.reputation => full ?? const SizedBox.shrink(),
              MyAccountSection.payment => PaymentRecipientSettings(
                gateway: _paymentGateway,
              ),
              MyAccountSection.security => _buildSecuritySection(),
              MyAccountSection.notifications => _buildNotificationsSection(),
            },
          ),
      ],
    );
  }

  Widget _buildSectionNavigation(double width) {
    final sections = _sections;
    if (width < 760) {
      return DropdownButtonFormField<MyAccountSection>(
        key: const ValueKey('my-account-mobile-section-navigation'),
        initialValue: sections.contains(_selectedSection)
            ? _selectedSection
            : MyAccountSection.profile,
        decoration: const InputDecoration(labelText: 'Account section'),
        items: [
          for (final section in sections)
            DropdownMenuItem(
              value: section,
              child: Row(
                children: [
                  Icon(section.icon, size: 20),
                  const SizedBox(width: 10),
                  Text(section.label),
                ],
              ),
            ),
        ],
        onChanged: _isBusy
            ? null
            : (section) {
                if (section != null) _selectSection(section);
              },
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final section in sections)
              ListTile(
                key: ValueKey('my-account-nav-${section.name}'),
                selected: section == _selectedSection,
                leading: Icon(section.icon),
                title: Text(section.label),
                onTap: _isBusy ? null : () => _selectSection(section),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_isBusy && !_hasUnsavedPersonalChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leaveAccount();
    },
    child: LoadingOverlay(
      isLoading: _isBusy,
      message: _isUploading
          ? 'Uploading photo...'
          : _isSaving
          ? 'Saving profile...'
          : _isSigningOut
          ? 'Signing out...'
          : 'Loading account...',
      child: AppWorkspace(
        title: 'My Account',
        path: AppRoutes.profile,
        role: _role,
        accountName: _savedName,
        accountAvatarUrl: _avatarUrl,
        navigationLocked: _isBusy || _isEditing,
        child: WorkspaceContent(
          maxWidth: 1180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProfileHeading(
                title: 'My Account',
                description: 'Manage your profile, security and role-specific account details.',
                icon: Icons.account_circle_outlined,
              ),
              if (_loadError != null)
                WorkspaceCard(
                  title: 'Account unavailable',
                  child: Column(
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _isBusy ? null : _loadProfile,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              else ...[
                WorkspaceCard(
                  title: 'Account overview',
                  child: _buildProfileHeader(),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 760
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 220,
                              child: _buildSectionNavigation(
                                constraints.maxWidth,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(child: _buildSectionContent()),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSectionNavigation(constraints.maxWidth),
                            const SizedBox(height: 20),
                            _buildSectionContent(),
                          ],
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
