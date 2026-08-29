import '../data/models/task.dart';
import 'telecom_service.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  Future<void> scheduleAlarm(Task task) async {
    await TelecomService.scheduleNativeAlarm(task);
  }
}
