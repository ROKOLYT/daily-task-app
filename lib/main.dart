// File: lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = true;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => TaskProvider(),
      child: MaterialApp(
        theme: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
        home: TaskScreen(
          isDarkMode: _isDarkMode,
          toggleTheme: _toggleTheme,
        ),
      ),
    );
  }
}

class Task {
  String title;
  bool isDone;

  Task({required this.title, this.isDone = false});

  Map<String, dynamic> toJson() => {
    'title': title,
    'isDone': isDone,
  };

  static Task fromJson(Map<String, dynamic> json) => Task(
    title: json['title'],
    isDone: json['isDone'],
  );
}

class TaskProvider with ChangeNotifier {
  List<Task> _tasks = [];
  late Timer _timer;

  TaskProvider() {
    loadTasks();
    _scheduleMidnightReset();
  }

  List<Task> get tasks => _tasks.where((task) => !task.isDone).toList();
  List<Task> get doneTasks => _tasks.where((task) => task.isDone).toList();

  void addTask(Task task) {
    _tasks.add(task);
    saveTasks();
    notifyListeners();
  }

  void toggleTaskStatus(Task task) {
    task.isDone = !task.isDone;
    saveTasks();
    notifyListeners();
  }

  void deleteTask(Task task) {
    _tasks.remove(task);
    saveTasks();
    notifyListeners();
  }

  void resetTasks() {
    for (var task in _tasks) {
      task.isDone = false;
    }
    saveTasks();
    notifyListeners();
  }

  void _scheduleMidnightReset() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final difference = nextMidnight.difference(now);

    _timer = Timer(difference, () {
      resetTasks();
      _scheduleMidnightReset();
    });
  }

  Future<void> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksData = prefs.getStringList('tasks') ?? [];
    _tasks = tasksData.map((task) => Task.fromJson(jsonDecode(task))).toList();
    notifyListeners();
  }

  Future<void> saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksData = _tasks.map((task) => jsonEncode(task.toJson())).toList();
    prefs.setStringList('tasks', tasksData);
  }
}

class TaskScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback toggleTheme;

  TaskScreen({required this.isDarkMode, required this.toggleTheme});

  @override
  _TaskScreenState createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> with TickerProviderStateMixin {
  final _taskController = TextEditingController();
  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  late Timer _timer;
  late String _timeLeft;
  late AnimationController _trashController;

  @override
  void initState() {
    super.initState();
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    final initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    _flutterLocalNotificationsPlugin.initialize(initializationSettings);

    _timeLeft = _formatTimeLeft();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _timeLeft = _formatTimeLeft();
      });
    });

    _trashController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
  }

  String _formatTimeLeft() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final difference = midnight.difference(now);

    return '${difference.inHours.toString().padLeft(2, '0')}:${(difference.inMinutes % 60).toString().padLeft(2, '0')}:${(difference.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _addTask() {
    final taskTitle = _taskController.text;
    if (taskTitle.isNotEmpty) {
      Provider.of<TaskProvider>(context, listen: false)
          .addTask(Task(title: taskTitle));
      _taskController.clear();
    }
  }

  Future<void> _scheduleNotification(String taskTitle) async {
    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'your_channel_id', // channel ID
      'your_channel_name', // channel name
      channelDescription: 'your_channel_description', // channel description
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    final platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin.show(
      0,
      'Task Reminder',
      taskTitle,
      platformChannelSpecifics,
    );
  }

  void _simulateEndOfDay() {
    Provider.of<TaskProvider>(context, listen: false).resetTasks();
  }

  void _playTrashAnimation() {
    _trashController.forward().then((_) {
      _trashController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _timeLeft,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Tasks'),
              Tab(text: 'Done'),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: _taskController,
                        decoration: InputDecoration(
                          labelText: 'New Task',
                          suffixIcon: IconButton(
                            icon: Icon(Icons.add),
                            onPressed: _addTask,
                          ),
                          border: InputBorder.none, // Remove underline
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: taskProvider.tasks.length,
                        itemBuilder: (context, index) {
                          final task = taskProvider.tasks[index];
                          return Dismissible(
                            key: Key(task.title),
                            onDismissed: (direction) {
                              taskProvider.toggleTaskStatus(task);
                            },
                            background: Container(
                              color: Colors.green,
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.only(left: 20.0),
                              child: Icon(Icons.check, color: Colors.black),
                            ),
                            child: ListTile(
                              title: Text(task.title),
                              leading: Icon(Icons.check, color: Colors.green, size: 20, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                              trailing: IconButton(
                                icon: AnimatedBuilder(
                                  animation: _trashController,
                                  builder: (context, child) {
                                    return Transform.rotate(
                                      angle: _trashController.value * 2.0 * 3.1416,
                                      child: Icon(Icons.delete, color: Colors.grey, size: 20, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                                    );
                                  },
                                ),
                                onPressed: () {
                                  _playTrashAnimation();
                                  Future.delayed(Duration(milliseconds: 500), () {
                                    taskProvider.deleteTask(task);
                                  });
                                },
                              ),
                              onTap: () {
                                _scheduleNotification(task.title);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                ListView.builder(
                  itemCount: taskProvider.doneTasks.length,
                  itemBuilder: (context, index) {
                    final task = taskProvider.doneTasks[index];
                    return Dismissible(
                      key: Key(task.title),
                      onDismissed: (direction) {
                        taskProvider.toggleTaskStatus(task);
                      },
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.only(left: 20.0),
                        child: Icon(Icons.close, color: Colors.black),
                      ),
                      child: ListTile(
                        title: Text(task.title),
                        leading: IconButton(
                          icon: Icon(Icons.close, color: Colors.red, size: 20, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                          onPressed: () {
                            taskProvider.toggleTaskStatus(task);
                          },
                        ),
                        trailing: IconButton(
                          icon: AnimatedBuilder(
                            animation: _trashController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _trashController.value * 2.0 * 3.1416,
                                child: Icon(Icons.delete, color: Colors.grey, size: 20, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                              );
                            },
                          ),
                          onPressed: () {
                            _playTrashAnimation();
                            Future.delayed(Duration(milliseconds: 500), () {
                              taskProvider.deleteTask(task);
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: widget.toggleTheme,
                child: Icon(
                  widget.isDarkMode ? Icons.wb_sunny : Icons.nights_stay,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _taskController.dispose();
    _timer.cancel();
    _trashController.dispose();
    super.dispose();
  }
}
