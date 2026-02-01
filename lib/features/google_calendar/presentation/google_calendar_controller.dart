import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/google/google_auth_service.dart';
import '../../../core/google/google_calendar_service.dart';
import '../../../app/providers.dart';

class GoogleCalendarController extends ChangeNotifier {
  GoogleCalendarController({
    required this.authService,
    required this.calendarService,
  });

  final GoogleAuthService authService;
  final GoogleCalendarService calendarService;

  DateTime _currentMonth = DateTime.now();
  DateTime get currentMonth => _currentMonth;

  DateTime? _selectedDate;
  DateTime? get selectedDate => _selectedDate;

  bool _showingEventForm = false;
  bool get showingEventForm => _showingEventForm;

  void setCurrentMonth(DateTime month) {
    _currentMonth = DateTime(month.year, month.month, 1);
    notifyListeners();
  }

  void nextMonth() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    notifyListeners();
  }

  void previousMonth() {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    notifyListeners();
  }

  void selectDate(DateTime? date) {
    _selectedDate = date;
    notifyListeners();
  }

  void showEventForm() {
    _showingEventForm = true;
    notifyListeners();
  }

  void hideEventForm() {
    _showingEventForm = false;
    notifyListeners();
  }

  void goToToday() {
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _selectedDate = now;
    notifyListeners();
  }
}

final googleCalendarControllerProvider =
    ChangeNotifierProvider<GoogleCalendarController>((ref) {
      final authService = ref.read(googleAuthServiceProvider);
      final calendarService = ref.read(googleCalendarServiceProvider);

      return GoogleCalendarController(
        authService: authService,
        calendarService: calendarService,
      );
    });
