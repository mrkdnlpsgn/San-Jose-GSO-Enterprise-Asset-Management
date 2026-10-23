import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/model/user_model.dart';

/// The user's profile picture, or their initial on brand green - same as the web's UserAvatar.
class UserAvatar extends StatelessWidget {
  final UserModel? user;
  final double size;
  const UserAvatar({super.key, required this.user, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName ?? '';
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppTheme.brandButton, shape: BoxShape.circle),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4),
      ),
    );
    final url = user?.avatarUrl;
    if (url == null || url.isEmpty) return initial;

    // Uploads are served from the backend root, outside /api.
    final base = ApiClient.instance.dio.options.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    return ClipOval(
      child: Image.network(
        url.startsWith('http') ? url : '$base$url',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initial,
      ),
    );
  }
}
