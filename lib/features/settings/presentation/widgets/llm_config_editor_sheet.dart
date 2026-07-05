import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_controller.dart';
import '../../../../app/model_controller.dart';
import '../../../../app/providers.dart';
import '../../../../core/model/model_descriptor.dart';

class LlmConfigEditorSheet extends ConsumerStatefulWidget {
  const LlmConfigEditorSheet({super.key, required this.model});

  final InstalledModel model;

  @override
  ConsumerState<LlmConfigEditorSheet> createState() => _LlmConfigEditorSheetState();
}

class _LlmConfigEditorSheetState extends ConsumerState<LlmConfigEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late String _type;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _tokenBufferController;
  late final TextEditingController _randomSeedController;
  late double _temperature;
  late final TextEditingController _topKController;
  late bool _topPEnabled;
  late double _topP;
  late bool _isThinking;
  late bool _supportsFunctionCalls;
  late ModelFileType _fileType;

  bool _saving = false;

  static const List<String> _modelTypes = [
    'qwen',
    'deepseek',
    'gemmait',
    'llama',
    'hammer',
    'functiongemma',
    'general',
  ];

  @override
  void initState() {
    super.initState();
    final config = widget.model.config;
    _type = config.type;
    _maxTokensController = TextEditingController(text: config.maxTokens.toString());
    _tokenBufferController = TextEditingController(text: config.tokenBuffer.toString());
    _randomSeedController = TextEditingController(text: config.randomSeed.toString());
    _temperature = config.temperature;
    _topKController = TextEditingController(text: config.topK.toString());
    _topPEnabled = config.topP != null;
    _topP = config.topP ?? 0.9;
    _isThinking = config.isThinking;
    _supportsFunctionCalls = config.supportsFunctionCalls;
    _fileType = config.fileType;
  }

  @override
  void dispose() {
    _maxTokensController.dispose();
    _tokenBufferController.dispose();
    _randomSeedController.dispose();
    _topKController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final nextConfig = LlmModelConfig(
        type: _type,
        maxTokens: int.parse(_maxTokensController.text),
        tokenBuffer: int.parse(_tokenBufferController.text),
        randomSeed: int.parse(_randomSeedController.text),
        temperature: _temperature,
        topK: int.parse(_topKController.text),
        topP: _topPEnabled ? _topP : null,
        isThinking: _isThinking,
        supportsFunctionCalls: _supportsFunctionCalls,
        fileType: _fileType,
      );

      final ModelController models = ref.read(modelControllerProvider);
      final AppController app = ref.read(appControllerProvider);

      await models.updateModelConfig(widget.model.id, nextConfig);

      if (models.selectedModelId == widget.model.id) {
        await app.activateSelectedModel();
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration saved!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save config: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _buildHeader(),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionCard(
                        title: 'CORE SETTINGS',
                        icon: Icons.settings_applications_rounded,
                        children: [
                          _buildDropdownField<String>(
                            label: 'Model Type',
                            value: _modelTypes.contains(_type) ? _type : 'qwen',
                            items: _modelTypes,
                            itemLabelBuilder: (v) => v.toUpperCase(),
                            onChanged: (v) {
                              if (v != null) setState(() => _type = v);
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildDropdownField<ModelFileType>(
                            label: 'File Type',
                            value: _fileType,
                            items: ModelFileType.values,
                            itemLabelBuilder: (v) => v.name.toUpperCase(),
                            onChanged: (v) {
                              if (v != null) setState(() => _fileType = v);
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _maxTokensController,
                                  label: 'Max Tokens',
                                  hint: '4096',
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final val = int.tryParse(v);
                                    if (val == null || val <= 0) {
                                      return 'Must be > 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _tokenBufferController,
                                  label: 'Token Buffer',
                                  hint: '512',
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final val = int.tryParse(v);
                                    if (val == null || val < 0) {
                                      return 'Must be >= 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildSectionCard(
                        title: 'HYPER-PARAMETERS',
                        icon: Icons.tune_rounded,
                        children: [
                          _buildSliderRow(
                            label: 'Temperature',
                            value: _temperature,
                            min: 0.0,
                            max: 2.0,
                            divisions: 200,
                            onChanged: (v) => setState(() => _temperature = v),
                          ),
                          const SizedBox(height: 12),
                          _buildTopPSlider(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _topKController,
                                  label: 'Top K',
                                  hint: '1',
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final val = int.tryParse(v);
                                    if (val == null || val <= 0) {
                                      return 'Must be > 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _randomSeedController,
                                  label: 'Random Seed',
                                  hint: '1',
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final val = int.tryParse(v);
                                    if (val == null) {
                                      return 'Must be integer';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildSectionCard(
                        title: 'CAPABILITIES',
                        icon: Icons.bolt_rounded,
                        children: [
                          _buildSwitchRow(
                            label: 'Is Thinking',
                            subtitle: 'Enable model internal reasoning steps',
                            value: _isThinking,
                            onChanged: (v) => setState(() => _isThinking = v),
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 10),
                          _buildSwitchRow(
                            label: 'Supports Function Calls',
                            subtitle: 'Allow assistant to run native tools',
                            value: _supportsFunctionCalls,
                            onChanged: (v) => setState(() => _supportsFunctionCalls = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.tune_rounded,
          color: Colors.white.withValues(alpha: 0.85),
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Configure Model: ${widget.model.id}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.75)),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required TextInputType keyboardType,
    required String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 14),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: items
                  .map(
                    (v) => DropdownMenuItem<T>(
                      value: v,
                      child: Text(itemLabelBuilder(v)),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTopPSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Top P',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 20,
                  width: 32,
                  child: FittedBox(
                    child: Switch(
                      value: _topPEnabled,
                      onChanged: (v) {
                        setState(() => _topPEnabled = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (_topPEnabled)
              Text(
                _topP.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              )
            else
              Text(
                'Disabled',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
        if (_topPEnabled) ...[
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: _topP,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              onChanged: (v) {
                setState(() => _topP = v);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 28,
          child: FittedBox(
            child: Switch(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
