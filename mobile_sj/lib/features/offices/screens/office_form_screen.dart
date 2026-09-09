import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/data/reference_service.dart';
import '../../../shared/utils/idempotency.dart';
import '../../accounts/data/account_service.dart';
import '../../accounts/model/account_model.dart';
import '../../assets/model/asset_model.dart';

class OfficeFormScreen extends StatefulWidget {
  final OfficeModel? office; // null = create, non-null = edit
  const OfficeFormScreen({super.key, this.office});

  @override
  State<OfficeFormScreen> createState() => _OfficeFormScreenState();
}

class _OfficeFormScreenState extends State<OfficeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _loadingUsers = true;
  final String _idempotencyKey = newIdempotencyKey();

  late final TextEditingController _name;
  int? _headUserId;
  List<AccountModel> _users = [];

  bool get _isEdit => widget.office != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.office?.officeName ?? '');
    _headUserId = widget.office?.headUserId;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await AccountService().getAll();
      if (mounted) setState(() { _users = users; _loadingUsers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final service = ReferenceService();
      final name = _name.text.trim();
      if (_isEdit) {
        await service.updateOffice(widget.office!.id, name, _headUserId);
      } else {
        await service.createOffice(name, _headUserId, idempotencyKey: _idempotencyKey);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Office' : 'New Office')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Office Name', hintText: 'e.g. Office of the Mayor'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<int?>(
                initialValue: _headUserId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Head User (optional)',
                  hintText: _loadingUsers ? 'Loading users…' : null,
                ),
                dropdownColor: context.colors.surface,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('— None —')),
                  ..._users.map((u) => DropdownMenuItem<int?>(
                        value: u.id,
                        child: Text(u.fullName.isNotEmpty ? u.fullName : u.username, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: _loadingUsers ? null : (v) => setState(() => _headUserId = v),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Save Changes' : 'Add Office'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
