import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:product_inventory/model/address.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/messenger.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final DatabaseService _database = DatabaseService();
  final AuthService _auth = AuthService();
  late final Stream<UserData?> _profileStream = _database.userProfileStream(
    widget.uid,
  );
  bool _deleting = false;

  Future<void> _editProfile(UserData profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditProfileScreen(uid: widget.uid, profile: profile),
      ),
    );
  }

  Future<void> _openAddresses() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddressesScreen(uid: widget.uid)),
    );
  }

  Future<void> _logOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to log out: $error')));
    }
  }

  Future<void> _deleteAccount(UserData profile) async {
    setState(() => _deleting = true);
    bool dataRemoved = false;
    try {
      final bool hasActiveOrders = await _database.hasActiveOrders(
        widget.uid,
        profile.role,
      );
      if (!mounted) return;
      if (hasActiveOrders) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You cannot delete your account while you have active orders.',
            ),
          ),
        );
        return;
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'This permanently deletes your profile and saved account data. '
            'Your completed order history will remain.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      final TextEditingController passwordController = TextEditingController();
      final String? password = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Confirm your password'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(passwordController.text),
              child: const Text('Delete account'),
            ),
          ],
        ),
      );
      passwordController.dispose();
      if (!mounted || password == null) return;
      if (password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your password to continue.')),
        );
        return;
      }

      await _auth.reauthenticate(password);
      await _database.deleteAccountData(widget.uid, profile.role);
      dataRemoved = true;
      await _auth.deleteCurrentUser();
    } catch (error) {
      debugPrint('Account deletion failed: $error');
      if (dataRemoved) {
        try {
          await _auth.signOut();
        } catch (signOutError) {
          debugPrint(
            'Sign out after incomplete account deletion failed: $signOutError',
          );
        }
        rootMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Your account data was removed, but account deletion could not finish. '
              'Sign in again and try deleting the account again.',
            ),
          ),
        );
      } else {
        final String message =
            error is FirebaseAuthException &&
                error.code == 'requires-recent-login'
            ? 'Please sign in again before deleting your account.'
            : 'Could not delete your account: $error';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _auth.currentFirebaseUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<UserData?>(
        stream: _profileStream,
        builder: (BuildContext context, AsyncSnapshot<UserData?> snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load your profile: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final UserData? profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('Your profile is unavailable.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              CircleAvatar(
                radius: 36,
                child: Text(
                  profile.firstName.isEmpty
                      ? '?'
                      : profile.firstName.substring(0, 1).toUpperCase(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                profile.fullName,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _ProfileValue(label: 'Email', value: user?.email ?? 'Not set'),
              _ProfileValue(
                label: 'Phone',
                value: profile.phone?.isNotEmpty == true
                    ? profile.phone!
                    : 'Not set',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _deleting ? null : () => _editProfile(profile),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
              if (profile.role == UserRole.customer)
                OutlinedButton.icon(
                  onPressed: _deleting ? null : _openAddresses,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('My addresses'),
                ),
              const SizedBox(height: 16),
              if (_deleting)
                const Center(child: CircularProgressIndicator())
              else
                TextButton.icon(
                  onPressed: () => _deleteAccount(profile),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete account'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              TextButton.icon(
                onPressed: _deleting ? null : _logOut,
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileValue extends StatelessWidget {
  const _ProfileValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.uid,
    required this.profile,
  });

  final String uid;
  final UserData profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final DatabaseService _database = DatabaseService();
  late final TextEditingController _firstNameController = TextEditingController(
    text: widget.profile.firstName,
  );
  late final TextEditingController _lastNameController = TextEditingController(
    text: widget.profile.lastName,
  );
  late final TextEditingController _phoneController = TextEditingController(
    text: widget.profile.phone ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateName(String? value, String label) {
    final String name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your $label.';
    if (name.length > 50) return '$label must be 50 characters or fewer.';
    return null;
  }

  String? _validatePhone(String? value) {
    final String phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;
    final int digits = phone.replaceAll(RegExp(r'\D'), '').length;
    if (digits < 7 ||
        phone.length > 30 ||
        !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone)) {
      return 'Enter a valid phone number with at least 7 digits.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _database.updateUserProfile(
        widget.uid,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phone: _phoneController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save profile: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String email = AuthService().currentFirebaseUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            TextFormField(
              controller: _firstNameController,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'First name'),
              validator: (String? value) => _validateName(value, 'first name'),
            ),
            TextFormField(
              controller: _lastNameController,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Last name'),
              validator: (String? value) => _validateName(value, 'last name'),
            ),
            TextFormField(
              initialValue: email,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextFormField(
              controller: _phoneController,
              maxLength: 30,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+63 912 345 6789',
              ),
              validator: _validatePhone,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, required this.uid});

  final String uid;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final DatabaseService _database = DatabaseService();
  late final Stream<List<Address>> _addressesStream = _database.addressesStream(
    widget.uid,
  );

  Future<void> _openForm({Address? address}) async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AddressFormScreen(uid: widget.uid, address: address),
      ),
    );
  }

  Future<void> _delete(Address address) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text('Remove "${address.label}" from your saved addresses?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _database.deleteAddress(widget.uid, address.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete address: $error')),
      );
    }
  }

  Future<void> _setDefault(Address address) async {
    try {
      await _database.setDefaultAddress(widget.uid, address.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not set default: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
      body: StreamBuilder<List<Address>>(
        stream: _addressesStream,
        builder: (BuildContext context, AsyncSnapshot<List<Address>> snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load addresses: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Address> addresses = snapshot.data!;
          if (addresses.isEmpty) {
            return const Center(child: Text('You have no saved addresses.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final Address address = addresses[index];
              return Card(
                child: ListTile(
                  onTap: () => _openForm(address: address),
                  title: Row(
                    children: <Widget>[
                      Expanded(child: Text(address.label)),
                      if (address.isDefault) const Chip(label: Text('Default')),
                    ],
                  ),
                  subtitle: Text(
                    '${address.recipient} · ${address.phone}\n${address.oneLine}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (String action) {
                      if (action == 'default') _setDefault(address);
                      if (action == 'edit') _openForm(address: address);
                      if (action == 'delete') _delete(address);
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          if (!address.isDefault)
                            const PopupMenuItem<String>(
                              value: 'default',
                              child: Text('Set as default'),
                            ),
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, required this.uid, this.address});

  final String uid;
  final Address? address;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final DatabaseService _database = DatabaseService();
  late final Map<String, TextEditingController>
  _controllers = <String, TextEditingController>{
    'label': TextEditingController(text: widget.address?.label ?? ''),
    'recipient': TextEditingController(text: widget.address?.recipient ?? ''),
    'phone': TextEditingController(text: widget.address?.phone ?? ''),
    'street': TextEditingController(text: widget.address?.street ?? ''),
    'barangay': TextEditingController(text: widget.address?.barangay ?? ''),
    'city': TextEditingController(text: widget.address?.city ?? ''),
    'province': TextEditingController(text: widget.address?.province ?? ''),
    'postalCode': TextEditingController(text: widget.address?.postalCode ?? ''),
    'notes': TextEditingController(text: widget.address?.notes ?? ''),
  };
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isDefault = widget.address?.isDefault ?? false;
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label, int maxLength) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter $label.';
    if (text.length > maxLength) {
      return '$label must be $maxLength characters or fewer.';
    }
    return null;
  }

  String? _optional(String? value, String label, int maxLength) {
    if ((value?.trim().length ?? 0) > maxLength) {
      return '$label must be $maxLength characters or fewer.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final String id = await _database.saveAddress(
        widget.uid,
        Address(
          id: widget.address?.id ?? '',
          label: _controllers['label']!.text.trim(),
          recipient: _controllers['recipient']!.text.trim(),
          phone: _controllers['phone']!.text.trim(),
          street: _controllers['street']!.text.trim(),
          barangay: _controllers['barangay']!.text.trim(),
          city: _controllers['city']!.text.trim(),
          province: _controllers['province']!.text.trim(),
          postalCode: _controllers['postalCode']!.text.trim(),
          notes: _controllers['notes']!.text.trim(),
          isDefault: _isDefault,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop<String>(id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save address: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    int maxLength = 100,
    bool required = true,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: _controllers[key],
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (String? value) => _required(value, label.toLowerCase(), maxLength)
          : (String? value) => _optional(value, label.toLowerCase(), maxLength),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.address == null ? 'Add address' : 'Edit address'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _field('label', 'Address label', maxLength: 40),
            _field('recipient', 'Recipient name', maxLength: 100),
            _field(
              'phone',
              'Contact phone',
              maxLength: 30,
              keyboardType: TextInputType.phone,
            ),
            _field('street', 'House no. / street', maxLength: 150),
            _field('barangay', 'Barangay', maxLength: 100),
            _field('city', 'City / municipality', maxLength: 100),
            _field('province', 'Province', maxLength: 100),
            _field(
              'postalCode',
              'Postal code (optional)',
              required: false,
              maxLength: 20,
            ),
            _field(
              'notes',
              'Delivery notes (optional)',
              required: false,
              maxLength: 300,
              maxLines: 3,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (bool? value) =>
                  setState(() => _isDefault = value ?? false),
              title: const Text('Set as default address'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Save address'),
            ),
          ],
        ),
      ),
    );
  }
}
