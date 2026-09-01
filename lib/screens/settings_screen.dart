import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/managers/automix_manager.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
    required this.automixManager,
  });

  final StorageService storage;
  final AutomixManager automixManager;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late bool _timeStretchEnabled;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.storage.dspServerUrl);
    _timeStretchEnabled = widget.storage.timeStretchEnabled;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await widget.storage.setDspServerUrl(url);
    if (widget.automixManager.enabled) {
      unawaited(widget.automixManager.recheckHealthNow());
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sunucu adresi kaydedildi.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'DSP Sunucu Adresi',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Arama, çalma ve automix için kullanılan tek sunucu — another-dsp.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'http://127.0.0.1:8000',
                  ),
                  onSubmitted: (_) => _saveUrl(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: _saveUrl, child: const Text('Kaydet')),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(color: AppColors.surfaceBorder, height: 1),
          const SizedBox(height: AppSpacing.sm),
          AnimatedBuilder(
            animation: widget.automixManager,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automix'),
                  subtitle: const Text(
                    'Şarkılar arasında beat-matched, DSP destekli geçiş.',
                  ),
                  value: widget.automixManager.enabled,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) => widget.automixManager.setEnabled(v),
                ),
                if (widget.automixManager.enabled)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Zaman esnetme'),
                    subtitle: const Text(
                      'Tempoları uzak parçaları da eşleştirir; hız değişiminin '
                      'perde etkisi iptal edilir. Kapalıyken sadece %6\'ya kadar '
                      'esneme yapılır ve uyuşmayan çiftler kısa geçişe düşer.',
                    ),
                    value: _timeStretchEnabled,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) async {
                      await widget.storage.setTimeStretchEnabled(v);
                      if (!mounted) return;
                      setState(() => _timeStretchEnabled = v);
                    },
                  ),
                if (widget.automixManager.enabled)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          widget.automixManager.serverReachable
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          size: 16,
                          color: widget.automixManager.serverReachable
                              ? AppColors.automixGreen
                              : AppColors.automixRed,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.automixManager.serverReachable
                              ? 'Sunucuya bağlı'
                              : 'Sunucuya ulaşılamıyor',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.automixManager.serverReachable
                                ? AppColors.automixGreen
                                : AppColors.automixRed,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
