import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Pillbox',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _medicineNameController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  int _notificationId = 0;
  List<Map<String, String>> _reminders = [];

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    tz.initializeTimeZones();
    _loadReminders();
  }

  Future<void> _initializeNotifications() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification taps if needed
      },
    );

    // Request notification permissions for Android 13+ (API level 33 or higher)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Request permissions for iOS
    final iOSImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

    // Check if the implementation exists before calling requestPermissions
    if (iOSImpl != null) {
      await iOSImpl.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> scheduleNotification(String medicineName, TimeOfDay time) async {
    final now = DateTime.now();
    var scheduleTime = tz.TZDateTime.local(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // Reschedule to the next day if the time is in the past
    if (scheduleTime.isBefore(now)) {
      scheduleTime = scheduleTime.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      _notificationId++,
      'Time for your medicine',
      'It\'s time to take $medicineName',
      scheduleTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medicine_reminder_channel',
          'Medicine Reminder',
          channelDescription: 'Channel for medicine reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('reminders', jsonEncode(_reminders));
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final remindersString = prefs.getString('reminders');
    if (remindersString != null) {
      setState(() {
        _reminders = List<Map<String, String>>.from(
          jsonDecode(remindersString) as List,
        );
      });
    }
  }

  Future<TimeOfDay?> pickTime(BuildContext context) async {
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
  }

  void _addReminder(String medicineName, String time) {
    setState(() {
      _reminders.add({'medicine': medicineName, 'time': time});
    });
    _saveReminders();
  }

  void _removeReminder(int index) {
    setState(() {
      _reminders.removeAt(index);
    });
    _saveReminders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Pillbox'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _medicineNameController,
                    decoration: const InputDecoration(
                      labelText: 'Medicine Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the medicine name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _timeController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Time',
                      border: OutlineInputBorder(),
                    ),
                    onTap: () async {
                      final time = await pickTime(context);
                      if (time != null) {
                        _timeController.text = time.format(context);
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a time';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          final medicineName = _medicineNameController.text;
                          final time = _timeController.text;

                          _addReminder(medicineName, time);

                          final timeParts = time.split(' ');
                          final hourMinute = timeParts[0].split(':');
                          final hour = int.parse(hourMinute[0]) +
                              (timeParts[1] == 'PM' &&
                                  int.parse(hourMinute[0]) != 12
                                  ? 12
                                  : 0) -
                              (timeParts[1] == 'AM' &&
                                  int.parse(hourMinute[0]) == 12
                                  ? 12
                                  : 0);
                          final minute = int.parse(hourMinute[1]);

                          scheduleNotification(
                              medicineName, TimeOfDay(hour: hour, minute: minute));

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Reminder set for $medicineName'),
                            ),
                          );

                          _medicineNameController.clear();
                          _timeController.clear();
                        }
                      },
                      child: const Text('Set Reminder'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _reminders.length,
                itemBuilder: (context, index) {
                  final reminder = _reminders[index];
                  return Card(
                    child: ListTile(
                      title: Text(reminder['medicine']!),
                      subtitle: Text('Time: ${reminder['time']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          _removeReminder(index);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
