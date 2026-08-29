import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import 'package:carpediem/services/database_helper.dart';
import '../data/models/task.dart';

class CalendarHistoryScreen extends StatefulWidget {
  const CalendarHistoryScreen({super.key});

  @override
  State<CalendarHistoryScreen> createState() => _CalendarHistoryScreenState();
}

class _CalendarHistoryScreenState extends State<CalendarHistoryScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Task> _dayTasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDayTasks();
  }

  Future<void> _fetchDayTasks() async {
    setState(() => _loading = true);
    final all = await DatabaseHelper.instance.getAllTasks();
    final filtered = all.where((t) {
      final dt = t.dueDateTime;
      return dt.year == _selectedDate.year && dt.month == _selectedDate.month && dt.day == _selectedDate.day;
    }).toList();

    if (mounted) {
      setState(() {
        _dayTasks = filtered;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Calendar & History', style: GoogleFonts.outfit(color: AppColors.text, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2022),
            lastDate: DateTime(2030),
            onDateChanged: (date) {
              setState(() => _selectedDate = date);
              _fetchDayTasks();
            },
          ),
          const Divider(color: AppColors.divider),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _dayTasks.isEmpty
                    ? Center(child: Text('No tasks on this day', style: GoogleFonts.inter(color: AppColors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _dayTasks.length,
                        itemBuilder: (context, idx) {
                          final t = _dayTasks[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Icon(
                                  t.status == TaskStatusEnum.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: t.status == TaskStatusEnum.completed ? AppColors.success : AppColors.accent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(t.title, style: GoogleFonts.inter(color: AppColors.text, fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          )
        ],
      ),
    );
  }
}
