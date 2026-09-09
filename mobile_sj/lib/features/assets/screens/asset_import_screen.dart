import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/asset_service.dart';
import '../model/asset_import_result.dart';
import '../utils/asset_excel.dart';

const _requiredKeys = [
  'description', 'categoryName', 'officeName', 'accountablePerson',
  'physicalCount', 'acquisitionDate', 'unitValue', 'location', 'condition',
];

class AssetImportScreen extends StatefulWidget {
  const AssetImportScreen({super.key});

  @override
  State<AssetImportScreen> createState() => _AssetImportScreenState();
}

enum _Stage { idle, preview, importing, done }

class _AssetImportScreenState extends State<AssetImportScreen> {
  _Stage _stage = _Stage.idle;
  String? _fileName;
  String? _error;
  List<Map<String, String>> _rows = [];
  AssetImportResult? _result;
  bool _busy = false;

  Future<void> _pickFile() async {
    setState(() { _error = null; _busy = true; });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final rows = parseAssetImportBytes(bytes);
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _stage = _Stage.preview;
      });
    } on AssetImportParseException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Failed to read the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _stage = _Stage.importing);
    try {
      final result = await AssetService().bulkImport(_rows);
      setState(() { _result = result; _stage = _Stage.done; });
    } on ApiException catch (e) {
      setState(() {
        _result = AssetImportResult(
          saved: const [],
          failed: _rows.map((r) => AssetImportFailure(row: r, reason: e.message)).toList(),
        );
        _stage = _Stage.done;
      });
    }
  }

  void _reset() {
    setState(() {
      _stage = _Stage.idle;
      _fileName = null;
      _error = null;
      _rows = [];
      _result = null;
    });
  }

  List<int> get _invalidRowNumbers {
    final invalid = <int>[];
    for (var i = 0; i < _rows.length; i++) {
      final missing = _requiredKeys.any((k) => (_rows[i][k] ?? '').trim().isEmpty);
      if (missing) invalid.add(i + 1);
    }
    return invalid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Assets'),
        actions: [
          if (_stage == _Stage.idle)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download Template',
              onPressed: () => downloadImportTemplate(),
            ),
        ],
      ),
      body: switch (_stage) {
        _Stage.idle => _buildIdle(context),
        _Stage.preview => _buildPreview(context),
        _Stage.importing => _buildImporting(context),
        _Stage.done => _buildDone(context),
      },
    );
  }

  Widget _buildIdle(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_outlined, size: 56, color: context.colors.textTertiary),
            const SizedBox(height: 16),
            Text('Upload an XLSX file to create multiple assets at once',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 6),
            Text('Category and Office must match existing names exactly (case-insensitive)',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.folder_open_outlined),
                label: Text(_busy ? 'Reading…' : 'Choose File'),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => downloadImportTemplate(),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download Template'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade300, fontSize: 12.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final invalid = _invalidRowNumbers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: context.colors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fileName ?? '', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text('${_rows.length} record${_rows.length != 1 ? 's' : ''} ready to import',
                            style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _reset, child: const Text('Change')),
                ],
              ),
            ),
          ),
        ),
        if (invalid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${invalid.length} row${invalid.length != 1 ? 's' : ''} missing a required field and will fail: rows ${invalid.take(10).join(', ')}${invalid.length > 10 ? '…' : ''}',
                style: const TextStyle(color: Colors.amber, fontSize: 12.5),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final r = _rows[i];
              final rowInvalid = invalid.contains(i + 1);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: rowInvalid ? Colors.red.withValues(alpha: 0.15) : AppTheme.brand.withValues(alpha: 0.15),
                    child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: rowInvalid ? Colors.red : AppTheme.brand)),
                  ),
                  title: Text(r['description']?.isNotEmpty == true ? r['description']! : '(no description)',
                      style: TextStyle(color: context.colors.textPrimary, fontSize: 13.5)),
                  subtitle: Text('${r['categoryName'] ?? ''} · ${r['officeName'] ?? ''}',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _import,
              child: Text('Import ${_rows.length} Record${_rows.length != 1 ? 's' : ''}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImporting(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.brand),
          const SizedBox(height: 16),
          Text('Importing ${_rows.length} records…', style: TextStyle(color: context.colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final result = _result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (result.saved.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.failed.isNotEmpty
                        ? '${result.saved.length} imported, ${result.failed.length} failed'
                        : '${result.saved.length} asset${result.saved.length != 1 ? 's' : ''} imported successfully',
                    style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        if (result.failed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('${result.failed.length} row${result.failed.length != 1 ? 's' : ''} could not be saved',
              style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 8),
          ...result.failed.map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.row['description']?.toString().isNotEmpty == true ? f.row['description'].toString() : '(no description)',
                          style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(f.reason, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                    ],
                  ),
                ),
              )),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, result.saved.isNotEmpty),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
