import 'package:flutter/material.dart';

import '../../../../core/memory/memory_service.dart';

class MemoryEditorSheet extends StatefulWidget {
  const MemoryEditorSheet({
    super.key,
    required this.initialMemory,
    required this.initialAutoUpdate,
    required this.memoryService,
  });

  final UserMemory initialMemory;
  final bool initialAutoUpdate;
  final MemoryService memoryService;

  @override
  State<MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<MemoryEditorSheet> {
  late final TextEditingController _nameController;
  late List<String> _traits;
  late List<String> _preferences;
  late List<String> _goals;
  late List<String> _facts;
  late bool _autoUpdate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.initialMemory;
    _nameController = TextEditingController(text: m.name ?? '');
    _traits = List<String>.from(m.traits);
    _preferences = List<String>.from(m.preferences);
    _goals = List<String>.from(m.goals);
    _facts = List<String>.from(m.facts);
    _autoUpdate = widget.initialAutoUpdate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  UserMemory _buildMemory() {
    final name = _nameController.text.trim();
    return UserMemory(
      name: name.isEmpty ? null : name,
      traits: _traits,
      preferences: _preferences,
      goals: _goals,
      facts: _facts,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.memoryService.saveMemoryData(_buildMemory());
      await widget.memoryService.setAutoUpdateAllowed(_autoUpdate);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearAll() {
    setState(() {
      _nameController.clear();
      _traits.clear();
      _preferences.clear();
      _goals.clear();
      _facts.clear();
    });
  }

  void _addToList(List<String> list, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (list.length >= MemoryConfig.maxEntriesPerField) return;
    if (list.contains(trimmed)) return;
    setState(() => list.add(trimmed));
  }

  void _removeFromList(List<String> list, int index) {
    setState(() => list.removeAt(index));
  }

  Future<void> _showAddDialog({
    required String fieldLabel,
    required List<String> targetList,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _AddEntryDialog(fieldLabel: fieldLabel, controller: controller),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) {
      _addToList(targetList, result);
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
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: _buildHeader(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildNameField(),
                    const SizedBox(height: 16),
                    _buildTagSection(
                      icon: Icons.emoji_emotions_rounded,
                      label: 'Traits',
                      items: _traits,
                      color: const Color(0xFF64B5F6),
                      onAdd: () => _showAddDialog(
                        fieldLabel: 'Trait',
                        targetList: _traits,
                      ),
                      onRemove: (i) => _removeFromList(_traits, i),
                    ),
                    const SizedBox(height: 14),
                    _buildTagSection(
                      icon: Icons.favorite_rounded,
                      label: 'Preferences',
                      items: _preferences,
                      color: const Color(0xFFE57373),
                      onAdd: () => _showAddDialog(
                        fieldLabel: 'Preference',
                        targetList: _preferences,
                      ),
                      onRemove: (i) => _removeFromList(_preferences, i),
                    ),
                    const SizedBox(height: 14),
                    _buildTagSection(
                      icon: Icons.flag_rounded,
                      label: 'Goals',
                      items: _goals,
                      color: const Color(0xFF81C784),
                      onAdd: () => _showAddDialog(
                        fieldLabel: 'Goal',
                        targetList: _goals,
                      ),
                      onRemove: (i) => _removeFromList(_goals, i),
                    ),
                    const SizedBox(height: 14),
                    _buildTagSection(
                      icon: Icons.lightbulb_rounded,
                      label: 'Facts',
                      items: _facts,
                      color: const Color(0xFFFFD54F),
                      onAdd: () => _showAddDialog(
                        fieldLabel: 'Fact',
                        targetList: _facts,
                      ),
                      onRemove: (i) => _removeFromList(_facts, i),
                    ),
                    const SizedBox(height: 16),
                    _buildAutoUpdateToggle(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _buildSaveButton(),
            ),
          ],
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
          tooltip: 'Clear all memory',
          onPressed: _clearAll,
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.person_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              'Name',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: TextField(
            controller: _nameController,
            maxLength: 50,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'User\'s name',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              counterText: '',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagSection({
    required IconData icon,
    required String label,
    required List<String> items,
    required Color color,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
  }) {
    final atLimit = items.length >= MemoryConfig.maxEntriesPerField;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${items.length}/${MemoryConfig.maxEntriesPerField}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < items.length; i++)
                _MemoryChip(
                  label: items[i],
                  color: color,
                  onDelete: () => onRemove(i),
                ),
              if (!atLimit) _AddChipButton(color: color, onPressed: onAdd),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutoUpdateToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auto-update',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Learn from conversations automatically',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                value: _autoUpdate,
                onChanged: (v) => setState(() => _autoUpdate = v),
              ),
            ),
          ),
        ],
      ),
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

class _MemoryChip extends StatelessWidget {
  const _MemoryChip({
    required this.label,
    required this.color,
    required this.onDelete,
  });

  final String label;
  final Color color;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onDelete,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddChipButton extends StatelessWidget {
  const _AddChipButton({required this.color, required this.onPressed});

  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddEntryDialog extends StatelessWidget {
  const _AddEntryDialog({required this.fieldLabel, required this.controller});

  final String fieldLabel;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Add $fieldLabel',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        style: const TextStyle(fontSize: 14),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
        decoration: InputDecoration(
          hintText: 'Enter $fieldLabel…',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          counterText: '',
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.07),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
