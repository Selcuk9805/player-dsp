import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared loading/error placeholders for detail screens (artist/album/
/// playlist) that fetch a single resource from `another-dsp` on open.
class CollectionLoading extends StatelessWidget {
  const CollectionLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }
}

class CollectionError extends StatelessWidget {
  const CollectionError({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.textDisabled,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Yüklenemedi: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      ),
    );
  }
}
