import 'package:flutter/material.dart';

import '../../../../core/google/google_auth_service.dart';
import '../../../../shared/widgets/glass/glass.dart';

class GoogleSignInPrompt extends StatelessWidget {
  const GoogleSignInPrompt({
    super.key,
    required this.authService,
    this.onSignInComplete,
  });

  final GoogleAuthService authService;
  final VoidCallback? onSignInComplete;

  @override
  Widget build(BuildContext context) {
    final isLoading = authService.isLoading;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Connect Your Calendar',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in with Google to view and manage your calendar events.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _GoogleSignInButton(
                isLoading: isLoading,
                onPressed: () async {
                  final success = await authService.signIn();
                  if (success) {
                    onSignInComplete?.call();
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Your data stays private and secure.\nSign-in is optional for other app features.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4285F4),
                  ),
                )
              else
                Image.asset(
                  'assets/images/google_logo.png',
                  width: 20,
                  height: 20,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.g_mobiledata_rounded,
                      size: 24,
                      color: Color(0xFF4285F4),
                    );
                  },
                ),
              const SizedBox(width: 12),
              Text(
                isLoading ? 'Signing in...' : 'Sign in with Google',
                style: const TextStyle(
                  color: Color(0xFF3C4043),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
