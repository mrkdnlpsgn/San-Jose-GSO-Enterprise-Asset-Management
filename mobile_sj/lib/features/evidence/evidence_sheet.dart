import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import 'evidence_service.dart';

// image_picker has no live-camera implementation on Windows/Linux (only a file/gallery picker).
bool get _cameraSupported => kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

const _maxBytes = 10 * 1024 * 1024; // matches the backend's 10 MB limit

/// Bottom sheet for a record's evidence photos: take a photo or pick from the gallery to upload,
/// tap a photo to view it full-size, and remove one with the ✕.
/// `path` is the record's photo endpoint (see [EvidenceService]).
Future<void> showEvidenceSheet(
  BuildContext context, {
  required String path,
  required String title,
  String? subtitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _EvidenceSheet(service: EvidenceService(path), title: title, subtitle: subtitle),
    ),
  );
}

class _EvidenceSheet extends StatefulWidget {
  final EvidenceService service;
  final String title;
  final String? subtitle;

  const _EvidenceSheet({required this.service, required this.title, this.subtitle});

  @override
  State<_EvidenceSheet> createState() => _EvidenceSheetState();
}

class _EvidenceSheetState extends State<_EvidenceSheet> {
  List<EvidencePhoto>? _photos;
  Object? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final photos = await widget.service.list();
      if (mounted) setState(() => _photos = photos);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade800 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    final List<XFile> files;
    if (source == ImageSource.camera) {
      final one = await picker.pickImage(source: source, imageQuality: 85);
      files = one == null ? <XFile>[] : <XFile>[one];
    } else {
      files = await picker.pickMultiImage(imageQuality: 85);
    }
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    for (final f in files) {
      try {
        if (await f.length() > _maxBytes) {
          _toast('${f.name}: exceeds the 10 MB limit.', error: true);
          continue;
        }
        final photo = await widget.service.upload(f.path, f.name);
        if (mounted) setState(() => _photos = [photo, ...?_photos]);
      } catch (e) {
        _toast(e.toString(), error: true);
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _delete(EvidencePhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('This evidence photo will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.delete(photo.id);
      if (mounted) setState(() => _photos = _photos?.where((p) => p.id != photo.id).toList());
      _toast('Photo removed.');
    } catch (e) {
      _toast(e.toString(), error: true);
    }
  }

  void _view(EvidencePhoto photo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  photo.fullUrl,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            if (photo.originalFilename != null)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Text(photo.originalFilename!,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              if (widget.subtitle != null)
                Text(widget.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_cameraSupported)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Take photo'),
                  ),
                ),
              if (_cameraSupported) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('From gallery'),
                ),
              ),
            ],
          ),
        ),
        if (_uploading)
          const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(color: AppTheme.brand)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text('JPEG, PNG, WEBP, or HEIC — up to 10 MB each',
              style: TextStyle(color: context.colors.textTertiary, fontSize: 11.5)),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Text("Couldn't load evidence photos.", style: TextStyle(color: context.colors.textTertiary)))
              : photos == null
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.brand))
                  : photos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, size: 40, color: context.colors.textTertiary),
                              const SizedBox(height: 8),
                              Text('No evidence photos yet.', style: TextStyle(color: context.colors.textTertiary)),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: photos.length,
                          itemBuilder: (context, i) {
                            final photo = photos[i];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  InkWell(
                                    onTap: () => _view(photo),
                                    child: Image.network(
                                      photo.fullUrl,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (c, child, p) =>
                                          p == null ? child : Container(color: context.colors.surface),
                                      errorBuilder: (_, __, ___) => Container(
                                        color: context.colors.surface,
                                        child: Icon(Icons.broken_image_outlined, color: context.colors.textTertiary),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () => _delete(photo),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
