import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../shared/widgets/ui.dart';
import '../data/personnel_service.dart';

/// "Assign Offices" - the web's PersonnelModal. An account can be assigned several offices;
/// staff see the assets they're accountable for in all of them. Pops with the saved record.
class PersonnelFormScreen extends ConsumerStatefulWidget {
  final PersonnelRecord person;
  const PersonnelFormScreen({super.key, required this.person});

  @override
  ConsumerState<PersonnelFormScreen> createState() => _PersonnelFormScreenState();
}

class _PersonnelFormScreenState extends ConsumerState<PersonnelFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<int> _officeIds = [...widget.person.officeIds];
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

  // the primary office stays the same unless it was unchecked
  List<int> _primaryFirst() {
    final primary = widget.person.officeId;
    if (primary == null || !_officeIds.contains(primary)) return [..._officeIds];
    return [primary, ..._officeIds.where((id) => id != primary)];
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final saved = await PersonnelService().update(
        widget.person.id,
        officeIds: _primaryFirst(),
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
      appBar: AppBar(title: Text(p.officeId == null ? 'Assign Offices' : 'Change Offices')),
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
            // who this is for - name and role come from the account, not edited here
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
            FormField<List<int>>(
              validator: (_) => _officeIds.isEmpty ? 'Choose at least one office.' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Offices *',
                            style: TextStyle(color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      Text('${_officeIds.length} selected', style: TextStyle(color: c.textTertiary, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      border: Border.all(color: field.hasError ? AppTheme.statusDisposed : c.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    // The tiles paint their background and tap ripple on the nearest Material - give
                    // them one inside this box, clipped to it, or they slide past its edges on scroll.
                    child: Material(
                      color: c.surface,
                      clipBehavior: Clip.antiAlias,
                      borderRadius: BorderRadius.circular(9),
                      child: officesAsync.isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : ListView(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              children: [
                                for (final o in officesAsync.valueOrNull ?? const [])
                                  CheckboxListTile(
                                    dense: true,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    value: _officeIds.contains(o.id),
                                    title: Text(o.officeName, style: TextStyle(color: c.textPrimary, fontSize: 15)),
                                    onChanged: (v) => setState(() {
                                      v == true ? _officeIds.add(o.id) : _officeIds.remove(o.id);
                                      _error = null;
                                      field.didChange(_officeIds);
                                    }),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  if (field.hasError) ...[
                    const SizedBox(height: 6),
                    Text(field.errorText!, style: const TextStyle(color: AppTheme.statusDisposed, fontSize: 13)),
                  ],
                  const SizedBox(height: 6),
                  Text("Staff see and manage the assets they're accountable for in every office checked.",
                      style: TextStyle(color: c.textTertiary, fontSize: 13)),
                ],
              ),
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
