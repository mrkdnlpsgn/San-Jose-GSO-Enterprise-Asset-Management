import 'package:flutter/material.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/data/reference_service.dart';
import '../../../shared/utils/idempotency.dart';
import '../../assets/model/asset_model.dart';

class CategoryFormScreen extends StatefulWidget {
  final CategoryModel? category; // null = create, non-null = edit
  const CategoryFormScreen({super.key, this.category});

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final String _idempotencyKey = newIdempotencyKey();

  late final TextEditingController _name;
  late final TextEditingController _description;

  bool get _isEdit => widget.category != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.categoryName ?? '');
    _description = TextEditingController(text: widget.category?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final service = ReferenceService();
      final name = _name.text.trim();
      final desc = _description.text.trim();
      if (_isEdit) {
        await service.updateCategory(widget.category!.id, name, desc.isEmpty ? null : desc);
      } else {
        await service.createCategory(name, desc.isEmpty ? null : desc, idempotencyKey: _idempotencyKey);
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit Category' : 'New Category')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Category Name', hintText: 'e.g. Desktop Computer'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Brief description of this category…',
                  alignLabelWithHint: true,
                ),
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
                    : Text(_isEdit ? 'Save Changes' : 'Add Category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
