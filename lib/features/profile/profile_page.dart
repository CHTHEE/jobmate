import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/auth_layout.dart';
import 'change_password_page.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  String? _loadError;
  String _email = '';
  String _accountStatus = '';
  String _role = '';
  String _verificationStatus = '';
  String? _avatarUrl;

  DateTime? _createdAt;
  DateTime? _updatedAt;

  bool get _isBusy => _isLoading || _isSaving || _isUploading;
  bool _isUploading = false;

  bool get _canEdit => !_isBusy && _accountStatus == 'active';

  static const _profileColumns =
      'name, phone_num, status, role, verification_status,'
      'profile_image_url, created_at, updated_at';

  @override
  void initState() {
    super.initState();
    _loadProfile();
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
    if (!_canEdit) return;

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
        _updatedAt = DateTime.tryParse((saved['updated_at'] as String?) ?? '');
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

  Widget _infoRow(String title, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isBusy,
      message: _isSaving
          ? 'Uploading photo...'
          : _isSaving
          ? 'Saving profile...'
          : 'Loading profile...',
      child: Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: AuthLayout(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadError != null) ...[
                Text(_loadError ?? ''),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isBusy ? null : _loadProfile,
                  child: const Text('Try again'),
                ),
              ] else ...[
                const Text('Personal Details', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 16),

                Center(
                  child: ClipOval(
                    child: _avatarUrl == null || _avatarUrl!.isEmpty
                        ? const SizedBox(
                            width: 100,
                            height: 100,
                            child: Icon(Icons.person, size: 64),
                          )
                        : Image.network(
                            _avatarUrl!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox(
                                width: 100,
                                height: 100,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                  ),
                ),

                TextButton.icon(
                  onPressed: _canEdit ? _pickAvatar : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Change photo'),
                ),

                const SizedBox(height: 24),

                _infoRow('Role', _displayLabel(_role)),

                _infoRow('Account status', _displayLabel(_accountStatus)),

                _infoRow('Verification', _displayLabel(_verificationStatus)),

                const SizedBox(height: 16),
                const Text('Email'),
                Text(_email),
                const SizedBox(height: 24),
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
                if (_accountStatus != 'active')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Your account currently cannot edit'
                      'profile details.',
                    ),
                  ),
                FilledButton(
                  onPressed: _canEdit ? _saveProfile : null,
                  child: const Text('Save Changes'),
                ),

                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => const ChangePasswordPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.lock_outline),
                        label:const Text('Change password'),
                ),

                const SizedBox(height: 16),

                Text(
                  'Last updated: ${_formatDate(_updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),

                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Account details'),
                  children: [
                    _infoRow('Account created', _formatDate(_createdAt)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
