import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../shared/widgets/ui.dart';
import '../data/personnel_service.dart';
import '../../../shared/widgets/ios_pickers.dart';

/// "Assign Office" — the web's PersonnelModal. Pops with the saved record.
class PersonnelFormScreen extends ConsumerStatefulWidget {
  final PersonnelRecord person;
  const PersonnelFormScreen({super.key, required this.person});

  @override
  ConsumerState<PersonnelFormScreen> createState() => _PersonnelFormScreenState();
}

class _PersonnelFormScreenState extends ConsumerState<PersonnelFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late int? _officeId = widget.person.officeId;
  late final _position = TextEditingController(text: widget.person.position ?? '');
  late final _contact = TextEditingController(text: widget.person.contactInfo ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _position.dispose();
    _contact.dispose();
    super.dispose();
  }

  String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final saved = await PersonnelService().update(
        widget.person.id,
        officeId: _officeId!,
        position: _orNull(_position.text),
        contactInfo: _orNull(_contact.text),
      );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.person;
    final officesAsync = ref.watch(officesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(p.officeId == null ? 'Assign Office' : 'Change Office')),
      bottomNavigationBar: FormActionBar(
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // who this is for — name and role come from the account, not edited here
            Text(p.fullName, style: TextStyle(color: c.heading, fontSize: 20, fontWeight: FontWeight.w700)),
            if (p.username != null) ...[
              const SizedBox(height: 2),
              CodeText('@${p.username}', size: 14),
            ],
            const SizedBox(height: 18),
            if (_error != null) ...[
              Callout(_error!, tone: CalloutTone.error),
              const SizedBox(height: 16),
            ],
            IosSelectFormField<int>(
              initialValue: _officeId,
              isExpanded: true,
              dropdownColor: c.surface,
              decoration: InputDecoration(
                labelText: 'Office *',
                hintText: officesAsync.isLoading ? 'Loading offices…' : '— Select office —',
              ),
              items: [
                for (final o in officesAsync.valueOrNull ?? const [])
                  DropdownMenuItem(value: o.id, child: Text(o.officeName, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() { _officeId = v; _error = null; }),
              validator: (v) => v == null ? 'Office is required.' : null,
            ),
            if (officesAsync.hasError) ...[
              const SizedBox(height: 8),
              const Text("Couldn't load the offices. Pull back and try again.",
                  style: TextStyle(color: AppTheme.statusDisposed, fontSize: 14)),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _position,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Position (optional)',
                hintText: 'e.g. Administrative Aide IV',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contact,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Contact Info (optional)',
                hintText: 'Phone or email',
              ),
            ),
            const SizedBox(height: 16),
            Text('Name and role are managed on the Accounts page.',
                style: TextStyle(color: c.textTertiary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
