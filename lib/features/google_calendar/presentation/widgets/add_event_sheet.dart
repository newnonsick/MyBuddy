import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../shared/widgets/glass/glass.dart';

class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({
    super.key,
    required this.initialDate,
    required this.onEventCreated,
  });

  final DateTime initialDate;
  final VoidCallback onEventCreated;

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  bool _isAllDay = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialDate;
    _endDate = widget.initialDate;

    final now = TimeOfDay.now();
    _startTime = TimeOfDay(hour: now.hour + 1, minute: 0);
    _endTime = TimeOfDay(hour: now.hour + 2, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111217),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHandle(),
                const SizedBox(height: 16),
                _buildHeader(),
                const SizedBox(height: 24),
                _buildTitleField(),
                const SizedBox(height: 16),
                _buildDateTimeSection(),
                const SizedBox(height: 16),
                _buildLocationField(),
                const SizedBox(height: 16),
                _buildDescriptionField(),
                const SizedBox(height: 24),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.add_circle_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        const SizedBox(width: 12),
        Text(
          'New Event',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Event Title',
        hintText: 'Enter event title',
        prefixIcon: const Icon(Icons.edit_rounded),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a title';
        }
        return null;
      },
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildDateTimeSection() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'All-day event',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Switch(
                value: _isAllDay,
                onChanged: (value) {
                  setState(() => _isAllDay = value);
                },
              ),
            ],
          ),
          const Divider(height: 24),
          _buildDateTimePicker(
            label: 'Starts',
            date: _startDate,
            time: _startTime,
            showTime: !_isAllDay,
            onDateTap: () => _pickDate(isStart: true),
            onTimeTap: () => _pickTime(isStart: true),
          ),
          const SizedBox(height: 12),
          _buildDateTimePicker(
            label: 'Ends',
            date: _endDate,
            time: _endTime,
            showTime: !_isAllDay,
            onDateTap: () => _pickDate(isStart: false),
            onTimeTap: () => _pickTime(isStart: false),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    required DateTime date,
    required TimeOfDay time,
    required bool showTime,
    required VoidCallback onDateTap,
    required VoidCallback onTimeTap,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: onDateTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(_formatDate(date)),
                ],
              ),
            ),
          ),
        ),
        if (showTime) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: onTimeTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(_formatTime(time)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationField() {
    return TextFormField(
      controller: _locationController,
      decoration: InputDecoration(
        labelText: 'Location (optional)',
        hintText: 'Add location',
        prefixIcon: const Icon(Icons.location_on_outlined),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Description (optional)',
        hintText: 'Add description',
        alignLabelWithHint: true,
        prefixIcon: const Padding(
          padding: EdgeInsets.only(bottom: 48),
          child: Icon(Icons.notes_rounded),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            onPressed: _isLoading ? null : _createEvent,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create Event'),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart ? _startDate : _endDate;
    final result = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(surface: const Color(0xFF1A1A1D)),
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      setState(() {
        if (isStart) {
          _startDate = result;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = result;
        }
      });
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initialTime = isStart ? _startTime : _endTime;
    final result = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(surface: const Color(0xFF1A1A1D)),
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      setState(() {
        if (isStart) {
          _startTime = result;
        } else {
          _endTime = result;
        }
      });
    }
  }

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final calendarService = ref.read(googleCalendarServiceProvider);

      DateTime startDateTime;
      DateTime endDateTime;

      if (_isAllDay) {
        startDateTime = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
        );
        endDateTime = DateTime(
          _endDate.year,
          _endDate.month,
          _endDate.day,
        ).add(const Duration(days: 1));
      } else {
        startDateTime = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          _startTime.hour,
          _startTime.minute,
        );
        endDateTime = DateTime(
          _endDate.year,
          _endDate.month,
          _endDate.day,
          _endTime.hour,
          _endTime.minute,
        );
      }

      if (endDateTime.isBefore(startDateTime) ||
          endDateTime.isAtSameMomentAs(startDateTime)) {
        _showError('End time must be after start time');
        setState(() => _isLoading = false);
        return;
      }

      final result = await calendarService.createEvent(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        startTime: startDateTime,
        endTime: endDateTime,
        isAllDay: _isAllDay,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
      );

      if (!mounted) return;

      if (result.isSuccess) {
        widget.onEventCreated();
        Navigator.of(context).pop();
        _showSuccess('Event created successfully');
      } else {
        _showError(result.error ?? 'Failed to create event');
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to create event: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
