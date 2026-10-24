import 'package:flutter/material.dart';
import '../../../shared/widgets/ui.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/data/reference_service.dart';
import '../../../shared/utils/idempotency.dart';
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
  final String _idempotencyKey = newIdempotencyKey();

  late final TextEditingController _name;
  // Head is no longer set from this form; keep whatever the office already has.
  int? _headUserId;

  bool get _isEdit => widget.office != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.office?.officeName ?? '');
    _headUserId = widget.office?.headUserId;
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
      // main button stays in reach at the bottom, however long the form
      bottomNavigationBar: FormActionBar(child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save Changes' : 'Add Office'),
            ),
          )),
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
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
