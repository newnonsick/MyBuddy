import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/google/google_auth_service.dart';
import '../../../../shared/widgets/glass/glass.dart';

class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key, required this.authService});

  final GoogleAuthService authService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1A1A1D),
      onSelected: (value) => _handleMenuAction(context, ref, value),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildAvatar(context, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authService.displayName ?? 'User',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          authService.userEmail ?? '',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 20),
              SizedBox(width: 12),
              Text('Sign out'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'disconnect',
          child: Row(
            children: [
              Icon(
                Icons.link_off_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text(
                'Disconnect account',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      ],
      child: GlassPill(
        padding: const EdgeInsets.all(8),
        child: _buildAvatar(context, size: 28),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, {required double size}) {
    final photoUrl = authService.photoUrl;
    final displayName = authService.displayName;

    if (photoUrl != null) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildFallbackAvatar(context, displayName, size);
          },
        ),
      );
    }

    return _buildFallbackAvatar(context, displayName, size);
  }

  Widget _buildFallbackAvatar(
    BuildContext context,
    String? displayName,
    double size,
  ) {
    final initial = (displayName?.isNotEmpty == true)
        ? displayName![0].toUpperCase()
        : 'U';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'signout':
        _confirmSignOut(context, ref);
        break;
      case 'disconnect':
        _confirmDisconnect(context, ref);
        break;
    }
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text(
          'You can sign back in anytime to access your calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(googleAuthServiceProvider).signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _confirmDisconnect(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disconnect Account?'),
        content: const Text(
          'This will revoke all permissions and remove your Google account from this app. You\'ll need to grant permissions again if you sign in later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(googleAuthServiceProvider).disconnect();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}
