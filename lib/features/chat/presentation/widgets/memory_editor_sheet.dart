import 'package:flutter/material.dart';

import '../../../../core/memory/memory_service.dart';

class MemoryEditorSheet extends StatefulWidget {
  const MemoryEditorSheet({
    super.key,
    required this.initialMemory,
    required this.initialAutoUpdate,
    required this.memoryService,
  });

  final String initialMemory;
  final bool initialAutoUpdate;
  final MemoryService memoryService;

  @override
  State<MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<MemoryEditorSheet> {
  late final TextEditingController _controller;
  late bool _autoUpdate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMemory);
    _autoUpdate = widget.initialAutoUpdate;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.memoryService.saveMemory(_controller.text);
      await widget.memoryService.setAutoUpdateAllowed(_autoUpdate);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearMemory() async {
    _controller.clear();
    await widget.memoryService.saveMemory('');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildTextField(),
              const SizedBox(height: 12),
              _buildAutoUpdateToggle(),
              const SizedBox(height: 14),
              _buildSaveButton(),
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
          Icons.psychology_rounded,
          color: Colors.white.withValues(alpha: 0.85),
          size: 22,
        ),
        const SizedBox(width: 8),
        Text(
          'Memory',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(
            Icons.delete_outline_rounded,
            color: Colors.redAccent.withValues(alpha: 0.8),
            size: 20,
          ),
          tooltip: 'Clear memory',
          onPressed: _clearMemory,
        ),
      ],
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: _controller,
        maxLength: MemoryConfig.maxMemoryCharacters,
        maxLines: 5,
        minLines: 3,
        style: const TextStyle(fontSize: 14, height: 1.4),
        decoration: InputDecoration(
          hintText: 'No memory yet. The AI will learn about you over time…',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 14,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
          counterStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildAutoUpdateToggle() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auto-update memory',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Allow the model to update memory from conversations',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: _autoUpdate,
          onChanged: (v) => setState(() => _autoUpdate = v),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return FilledButton(
      onPressed: _saving ? null : _save,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
