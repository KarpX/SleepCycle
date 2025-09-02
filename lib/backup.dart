import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:whenishuoldgotosleep/notifications_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';
import 'package:another_flushbar/flushbar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationsService.initialize();
  await initializeDateFormatting('ru_RU', null);
  tz.initializeTimeZones();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getBool('isDarkMode') ?? false
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  void _toggleTheme(bool value) async {
    setState(() {
      _themeMode = value ? ThemeMode.dark : ThemeMode.light;
    });
    await prefs.setBool('isDarkMode', value);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MaterialApp(
          title: 'SleepingCycle',
          theme: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.deepPurple,
              secondary: Colors.deepPurpleAccent,
              onSurface: const Color.fromARGB(255, 77, 34, 151),
            ),
            primaryColorLight: const Color.fromARGB(255, 210, 194, 255),
          ),
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: Color.fromARGB(255, 150, 115, 216),
              secondary: Color.fromARGB(255, 108, 58, 195),
              onPrimary: const Color.fromARGB(255, 242, 220, 255),
              onSurface: const Color.fromARGB(255, 242, 220, 255),
              primaryContainer: const Color.fromARGB(255, 26, 21, 35),
            ),
            primaryColorLight: const Color.fromARGB(255, 40, 30, 56),
            primaryColorDark: const Color.fromARGB(255, 48, 37, 69),
          ),
          themeMode: _themeMode,
          home: MyHomePage(
            isDarkMode: _themeMode == ThemeMode.dark,
            onThemeChanged: _toggleTheme,
          ),
        );
      },
    );
  }
}

enum AppMode { awakening, sleeping }

class MyHomePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const MyHomePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late SharedPreferences prefs;
  late TimeOfDay _selectedTime;
  AppMode _currentMode = AppMode.awakening;

  bool enableBeforeSleepTime = false;
  bool isAnyNotification = false;
  int countItems = 6;
  int cycleDurationMinutes = 90;
  int beforeSleepTime = 14;
  final List<TimeOfDay> timeList = [];
  Map<int, Map<String, dynamic>> notificationsList = {};
  Set<int> selectedItems = {};
  bool isSelectedMode = false;
  bool isAnyNotificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _selectedTime = getAdjustedTime();
    _checkPermissons();
    _loadSettings();
  }

  Future<void> _checkPermissons() async {
    final status = await Permission.scheduleExactAlarm.status;
    if (!status.isGranted) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  Future<void> _saveCycleDuration(int minutes) async {
    await prefs.setInt('cycleDuration', minutes);
  }

  TimeOfDay getAdjustedTime() {
    DateTime now = DateTime.now();
    DateTime adjusted = now.add(Duration(hours: 7, minutes: 30));

    return TimeOfDay(hour: adjusted.hour, minute: adjusted.minute);
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepPurpleAccent,
              onPrimary: Colors.white,
              surface: Color.fromARGB(255, 211, 185, 255),
              onSurface: Color.fromARGB(255, 17, 5, 21),
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
        generateTimeList();
      });
      print('Выбрано время: ${_selectedTime.format(context)}');
    }
  }

  Future<void> _loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    Future<Map<int, Map<String, dynamic>>> futureMap = _loadNotificationList();
    notificationsList = await futureMap;
    _updateButtonState();
    print("notificationList: $notificationsList");
    setState(() {
      cycleDurationMinutes = prefs.getInt('cycleDuration') ?? 90;
      enableBeforeSleepTime = prefs.getBool('enableBeforeSleepTime') ?? false;
      beforeSleepTime = prefs.getInt('beforeSleepTime') ?? 14;
      generateTimeList();
    });
  }

  Future<void> _saveNotificationsList(
    Map<int, Map<String, dynamic>> list,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(
      list.map((key, value) => MapEntry(key.toString(), value)),
    );
    await prefs.setString('notificationsList', jsonString);
  }

  Future<Map<int, Map<String, dynamic>>> _loadNotificationList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('notificationsList') ?? '{}';
    final stringMap = Map<String, dynamic>.from(jsonDecode(jsonString));
    return stringMap.map(
      (key, value) =>
          MapEntry(int.parse(key), Map<String, dynamic>.from(value)),
    );
  }

  Future<void> _scheuleSleepReminder(TimeOfDay time) async {
    final now = DateTime.now();
    DateTime scheduledtime = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (scheduledtime.isBefore(now)) {
      scheduledtime = scheduledtime.add(const Duration(days: 1));
    }

    int id = time.hour * 60 + time.minute;
    print("планируем время отбоя");
    notificationsList.addAll({
      id: {"time": scheduledtime.toString(), "isActive": true, "days": []},
    });
    _saveNotificationsList(notificationsList);
    await NotificationsService.scheduleNotification(
      id: id,
      title: "Пора баиньки...",
      body: "Ваше оптимальное время для засыпания: ${time.format(context)}",
      scheduledTime: scheduledtime,
      days: NotificationHelper.formatNotificationsList(notificationsList[id]!),
    );

    setState(() {
      _updateButtonState();
    });
  }

  Future<void> _checkPermissionsAndSchedule(TimeOfDay time) async {
    if (Platform.isAndroid) {
      final status = await NotificationsService.requestAndroidPermissions();
      if (status != true) {
        _showPermissionDeniedMessage();
        return;
      }
    }
    if (Platform.isIOS) {
      final status = await NotificationsService.requestIOSPermissions();
      if (status != true) {
        _showPermissionDeniedMessage();
        return;
      }
    }

    await _scheuleSleepReminder(time);
  }

  void _showPermissionDeniedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Уведмоления запрещены. Разрешите в настройках"),
        action: SnackBarAction(
          label: "Настройки",
          onPressed: () => NotificationsService.openAppSettings(),
        ),
      ),
    );
  }

  void _updateButtonState() {
    print("меняем кнопку: ${notificationsList.isNotEmpty}");
    setState(() {
      isAnyNotification = notificationsList.isNotEmpty;
      isAnyNotificationEnabled = _checkIsAnyNotificationEnabled();
    });
  }

  void _toggleBeforeSleepTime(bool value) async {
    setState(() {
      enableBeforeSleepTime = value;
    });
    await prefs.setBool("enableBeforeSleepTime", value);
    generateTimeList();
  }

  void _changeBeforeSleepTime(int value) async {
    setState(() {
      beforeSleepTime = value;
    });
    await prefs.setInt('beforeSleepTime', value);
    generateTimeList();
  }

  void generateTimeList() {
    setState(() {
      timeList.clear();

      DateTime now = DateTime.now();
      debugPrint("selectedTime: $_selectedTime");
      DateTime curr = DateTime(
        now.year,
        now.month,
        now.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      for (int i = 0; i < countItems; i++) {
        curr = curr.subtract(
          Duration(
            hours: cycleDurationMinutes ~/ 60,
            minutes: cycleDurationMinutes % 60,
          ),
        );
        if (!enableBeforeSleepTime) {
          timeList.add(TimeOfDay(hour: curr.hour, minute: curr.minute));
        } else {
          DateTime beforeSleep = curr.subtract(
            Duration(minutes: beforeSleepTime),
          );
          timeList.add(
            TimeOfDay(hour: beforeSleep.hour, minute: beforeSleep.minute),
          );
        }
      }
    });
  }

  Widget _buildModeSwitcher() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeButton('Пробуждение', AppMode.awakening),
        SizedBox(width: 10.w),
        _modeButton('Засыпание', AppMode.sleeping),
      ],
    );
  }

  Widget _modeButton(String text, AppMode mode) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: _currentMode == mode
            ? Colors.white
            : Colors.white.withValues(alpha: 125),
      ),
      onPressed: () => setState(() {
        _currentMode = mode;
      }),
      child: Text(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: theme.primaryColorLight,
      appBar: AppBar(title: _buildModeSwitcher()),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Время пробуждения',
              style: TextStyle(
                fontSize: 40.sp,
                color: theme.colorScheme.onSurface,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            BigCard(selectedTime: _selectedTime),
            SizedBox(height: 20.h),
            ElevatedButton(
              onPressed: () => _selectTime(context),
              child: Text("Выбрать время", style: TextStyle(fontSize: 25.sp)),
            ),
            SizedBox(height: 20.h),
            Center(
              child: SizedBox(
                height: 120.h,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: AlwaysScrollableScrollPhysics(),
                  itemCount: timeList.isNotEmpty ? countItems : 0,
                  itemBuilder: (context, index) {
                    return InkWell(
                      onTap: () {
                        int id =
                            timeList[index].hour * 60 + timeList[index].minute;
                        if (!notificationsList.containsKey(id)) {
                          _checkPermissionsAndSchedule(timeList[index]);
                        }
                      },
                      onLongPress: () async {
                        setState(() {
                          int id =
                              timeList[index].hour * 60 +
                              timeList[index].minute;
                          _checkPermissionsAndSchedule(timeList[index]);
                          Future.delayed(Duration(milliseconds: 10), () async {
                            //стоит реализовать отмену уведомления через время, хотя я и не знаю как это сделать грамотно (возможно стоит реализовать через класс)
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NotificationSettings(
                                  id: id,
                                  notification: notificationsList[id]!,
                                  pageNum: 0,
                                ),
                              ),
                            );
                            if (result == 'cancel') {
                              await NotificationsService.cancelNotification(id);
                              setState(() {
                                notificationsList.remove(id);
                                _saveNotificationsList(notificationsList);
                              });
                            } else if (result != null) {
                              setState(() {
                                notificationsList[id]!['days'] = result['days'];
                                notificationsList[id]!['isActive'] = true;
                                _saveNotificationsList(notificationsList);
                              });
                            }
                            _updateButtonState();
                          });
                        });
                      },
                      child: Container(
                        width: 120.w,
                        margin: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          color:
                              notificationsList.containsKey(
                                timeList[index].hour * 60 +
                                    timeList[index].minute,
                              )
                              ? theme.primaryColorDark
                              : theme.primaryColor,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              SizedBox(height: 15.h),
                              Text(
                                "${timeList[index].hour.toString().padLeft(2, '0')} : ${timeList[index].minute.toString().padLeft(2, '0')}",
                                style: TextStyle(
                                  fontSize: 28.sp,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                              SizedBox(height: 15.h),
                              Text(
                                getSleepCyclesText(index + 1),
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                _showNotificationList(context);
              },
              icon: isAnyNotification
                  ? (isAnyNotificationEnabled
                        ? Icon(Icons.notifications_active_rounded)
                        : Icon(Icons.notifications))
                  : Icon(Icons.notifications_none),
              iconSize: 36.sp,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.colorScheme.primary,
        onPressed: () => _showSettingsDialog(context),
        tooltip: "Настройки",
        child: const Icon(Icons.settings),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  String getSleepCyclesText(int count) {
    int lastDigit = count % 10;
    int lastTwoDigits = count % 100;

    if (lastTwoDigits >= 11 && lastTwoDigits <= 14) {
      return "$count циклов";
    }

    switch (lastDigit) {
      case 1:
        return "$count цикл";
      case 2:
      case 3:
      case 4:
        return "$count цикла";
      default:
        return "$count циклов";
    }
  }

  void _showNotificationList(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Theme.of(context).primaryColorDark,
              insetPadding: EdgeInsets.all(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isSelectedMode)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 6.h),
                        child: Text(
                          "Уведомления",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28.sp,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),

                    if (isSelectedMode)
                      Stack(
                        children: [
                          Row(
                            children: [
                              SizedBox(width: 10.w),
                              IconButton(
                                iconSize: 24.sp,
                                onPressed: () {
                                  if (selectedItems.length ==
                                      notificationsList.length) {
                                    selectedItems.removeAll(
                                      notificationsList.keys,
                                    );
                                  } else {
                                    selectedItems.addAll(
                                      notificationsList.keys,
                                    );
                                  }
                                  setStateDialog(() {});
                                },
                                icon:
                                    selectedItems.length !=
                                        notificationsList.length
                                    ? Icon(Icons.circle_outlined)
                                    : Icon(Icons.check_circle_rounded),
                                tooltip: "Выделить всё",
                              ),
                              Spacer(),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    isSelectedMode = false;
                                    selectedItems.clear();
                                  });
                                  setStateDialog(() {});
                                },
                                child: Text(
                                  "Отмена",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22.sp,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                    decorationThickness: 1,
                                    decorationColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10.w),
                            ],
                          ),
                        ],
                      ),
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: ClampingScrollPhysics(),
                        itemCount: notificationsList.length,
                        itemBuilder: (context, index) {
                          final id = notificationsList.keys.elementAt(index);
                          String notification = notificationsList[id]!['time'];

                          final date = DateTime.parse(notification);
                          final formattedTime =
                              NotificationHelper.formatNotificationHHmm(date);

                          Icon selectedIcon = Icon(Icons.check_circle_rounded);

                          final notificationDays =
                              (notificationsList[id]!['days'] as List?)
                                  ?.map((e) => e as int)
                                  .toList() ??
                              [];
                          final now = DateTime.now();
                          final todayNotification = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            date.hour,
                            date.minute,
                          );
                          final retString = !now.isBefore(todayNotification)
                              ? "Завтра: ${now.add(Duration(days: 1)).day}"
                              : "Сегодня: ${DateTime.now().day}";

                          final isSelected = selectedItems.contains(id);

                          if (date.isBefore(now) && notificationDays.isEmpty) {
                            notificationsList[id]!['isActive'] = false;
                            print("NotificationDate: $date | Now: $now");
                          }
                          return Column(
                            children: [
                              SizedBox(height: 10.h),
                              Container(
                                height: 70.h,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(35),
                                  ),
                                  color: Theme.of(context).primaryColor,
                                ),
                                child: ListTile(
                                  selected: isSelected,
                                  onTap: () async {
                                    if (isSelectedMode) {
                                      setState(() {
                                        if (isSelected) {
                                          selectedItems.remove(id);
                                        } else {
                                          selectedItems.add(id);
                                        }
                                      });
                                      setStateDialog(() {});
                                    } else {
                                      final result = await Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  NotificationSettings(
                                                    id: id,
                                                    notification:
                                                        notificationsList[id]!,
                                                    pageNum: 1,
                                                  ),
                                            ),
                                          );
                                      if (result != null) {
                                        setState(() {
                                          notificationsList[id]!['days'] =
                                              result['days'];
                                          notificationsList[id]!['isActive'] =
                                              true;
                                          _saveNotificationsList(
                                            notificationsList,
                                          );
                                        });
                                      }
                                      setStateDialog(() {});
                                    }
                                  },
                                  onLongPress: () {
                                    if (mounted) {
                                      setState(() {
                                        if (isSelected) {
                                          selectedItems.remove(id);
                                        } else {
                                          selectedItems.add(id);
                                          isSelectedMode = true;
                                        }
                                      });
                                    }

                                    setStateDialog(() {});
                                  },
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 5.w,
                                    vertical: 8.h,
                                  ),
                                  title: Row(
                                    children: [
                                      if (isSelectedMode)
                                        Stack(
                                          children: [
                                            Positioned(
                                              child: IconButton(
                                                onPressed: () {
                                                  setState(() {
                                                    if (selectedItems.contains(
                                                      id,
                                                    )) {
                                                      selectedItems.remove(id);
                                                    } else {
                                                      selectedItems.add(id);
                                                    }
                                                  });

                                                  setStateDialog(() {});
                                                },
                                                icon: isSelected
                                                    ? selectedIcon
                                                    : Icon(
                                                        Icons.circle_outlined,
                                                      ),
                                                iconSize: 20.sp,
                                              ),
                                            ),
                                          ],
                                        ),
                                      SizedBox(
                                        width: isSelectedMode ? 1.w : 10.w,
                                      ),
                                      Expanded(
                                        child: Text(
                                          formattedTime,
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            fontSize: isSelectedMode
                                                ? 28.spMin
                                                : 34.spMin,
                                          ),
                                        ),
                                      ),

                                      if (notificationDays.isEmpty)
                                        Text(
                                          retString,
                                          style: TextStyle(fontSize: 14.sp),
                                        ),
                                      if (notificationDays.length == 7)
                                        Text(
                                          "Ежедневно",
                                          style: TextStyle(fontSize: 14.sp),
                                        ),
                                      if (notificationDays.isNotEmpty &&
                                          notificationDays.length < 7)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(7, (
                                            dayIndex,
                                          ) {
                                            final days = notificationDays;

                                            final isSelected = days.contains(
                                              dayIndex + 1,
                                            );
                                            final dayLables = [
                                              "Пн",
                                              "Вт",
                                              "Ср",
                                              "Чт",
                                              "Пт",
                                              "Сб",
                                              "Вс",
                                            ];
                                            return Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 1.2,
                                              ),
                                              child: CircleAvatar(
                                                radius: 8.sp,
                                                backgroundColor: isSelected
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary,
                                                child: Text(
                                                  dayLables[dayIndex],
                                                  style: TextStyle(
                                                    fontSize: 9.sp,
                                                    color: isSelected
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .onPrimary
                                                        : Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ),

                                      SizedBox(width: 2.w),
                                      SizedBox(
                                        width: 45.w,
                                        child: Transform.scale(
                                          scale: 0.7,
                                          child: CupertinoSwitch(
                                            value:
                                                notificationsList[id]!['isActive'],
                                            onChanged: (value) async {
                                              print(
                                                "Переключили уведомление $notification: $value",
                                              );
                                              if (!mounted) {
                                                return;
                                              }
                                              setState(() {
                                                notificationsList[id]!['isActive'] =
                                                    value;
                                                _updateButtonState();
                                              });

                                              if (value) {
                                                Flushbar(
                                                  messageSize: 18.sp,
                                                  flushbarPosition:
                                                      FlushbarPosition.TOP,
                                                  message:
                                                      "Уведомление установлено: $formattedTime",
                                                  duration: Duration(
                                                    seconds: 2,
                                                  ),
                                                  margin: EdgeInsets.all(16),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ).show(context);
                                                await _enableNotification(id);
                                              } else {
                                                await _disableNotification(id);
                                              }
                                              setStateDialog(() {});
                                            },
                                            activeColor: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 1.w),
                                    ],
                                  ),
                                ),
                              ),

                              SizedBox(height: 10.h),
                            ],
                          );
                        },
                      ),
                    ),
                    if (isSelectedMode)
                      Stack(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IgnorePointer(
                                ignoring: selectedItems.isEmpty,
                                child: Opacity(
                                  opacity: selectedItems.isEmpty ? 0.5 : 1.0,
                                  child: IconButton(
                                    onPressed: () async {
                                      await _cancelSelectedNotifications(
                                        selectedItems,
                                      );
                                      setState(() {
                                        print(
                                          "selectedItems: ${selectedItems.length}",
                                        );
                                        isSelectedMode = false;
                                      });

                                      setStateDialog(() {});
                                    },
                                    icon: Icon(Icons.delete),
                                    iconSize: 30.sp,
                                  ),
                                ),
                              ),
                              SizedBox(width: 20.w),
                              IgnorePointer(
                                ignoring: selectedItems.isEmpty,
                                child: Opacity(
                                  opacity: selectedItems.isEmpty ? 0.5 : 1.0,
                                  child: IconButton(
                                    onPressed: () async {
                                      await _switchSelectedNotifications(
                                        selectedItems,
                                      );
                                      setStateDialog(() {});
                                    },
                                    icon: Icon(Icons.access_alarm),
                                    iconSize: 25.sp,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _checkIsAnyNotificationEnabled() {
    bool p = false;

    if (notificationsList.isEmpty) {
      return p;
    }
    for (int i = 0; i < notificationsList.length; i++) {
      final id = notificationsList.keys.elementAt(i);
      if (notificationsList[id]!['isActive']) {
        p = true;
        break;
      }
    }
    return p;
  }

  Future<void> _switchSelectedNotifications(Set<int> list) async {
    if (list.isEmpty) {
      return;
    } else {
      bool p = true;

      for (int id in list) {
        if (notificationsList[id]!['isActive'] == false) {
          p = false;
          break;
        }
      }

      if (p) {
        for (int id in list) {
          notificationsList[id]!['isActive'] = false;
          await NotificationsService.cancelNotification(id);
        }
      } else {
        for (int id in list) {
          if (notificationsList[id]!['isActive'] == false) {
            _enableNotification(id);
          }
        }
      }
      _saveNotificationsList(notificationsList);
    }
  }

  Future<void> _cancelSelectedNotifications(Set<int> list) async {
    if (list.isEmpty) {
      return;
    } else if (notificationsList.length == list.length) {
      setState(() {
        notificationsList.clear();
      });
      await NotificationsService.cancelAllNotifications();
    } else {
      for (int id in list) {
        setState(() {
          notificationsList.remove(id);
        });

        await NotificationsService.cancelNotification(id);
      }
    }
    _saveNotificationsList(notificationsList);
    _updateButtonState();
    selectedItems.clear();
  }

  Future<void> _enableNotification(int id) async {
    final timeStr = notificationsList[id]!['time'];
    final time = DateTime.parse(timeStr);

    await _scheuleSleepReminder(TimeOfDay.fromDateTime(time));
  }

  Future<void> _disableNotification(int id) async {
    await NotificationsService.cancelNotification(id);
  }

  void _showSettingsDialog(BuildContext context) {
    final _cycleController = TextEditingController(
      text: cycleDurationMinutes.toString(),
    );
    final _beforeSleepController = TextEditingController(
      text: beforeSleepTime.toString(),
    );

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).dialogTheme.backgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 65,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                physics: ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: Text(
                        "Темная тема",
                        style: TextStyle(fontSize: 24.spMin),
                      ),
                      value: widget.isDarkMode,
                      onChanged: (value) {
                        widget.onThemeChanged(value);
                      },
                    ),
                    ListTile(
                      title: Text(
                        "Продолжительность цикла сна",
                        style: TextStyle(fontSize: 22.spMin),
                      ),
                      trailing: SizedBox(
                        width: 45.w,
                        height: 50.w,
                        child: TextFormField(
                          textInputAction: TextInputAction.done,
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final minutes = int.tryParse(value);
                            if (minutes != null &&
                                minutes >= 60 &&
                                minutes <= 180) {
                              setState(() {
                                cycleDurationMinutes =
                                    int.tryParse(value) ?? 90;
                              });
                              _saveCycleDuration(minutes);
                              generateTimeList();
                            }
                          },
                          controller: _cycleController,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24.spMin),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(
                        "Режим: время засыпания",
                        style: TextStyle(fontSize: 22.spMin),
                      ),
                      value: enableBeforeSleepTime,
                      onChanged: (value) {
                        setStateDialog(() {});
                        _toggleBeforeSleepTime(value);
                      },
                    ),
                    IgnorePointer(
                      ignoring: !enableBeforeSleepTime,
                      child: Opacity(
                        opacity: enableBeforeSleepTime ? 1.0 : 0.5,
                        child: ListTile(
                          title: Text(
                            "Время засыпания",
                            style: TextStyle(fontSize: 22.spMin),
                          ),
                          trailing: SizedBox(
                            width: 45.w,
                            height: 50.h,
                            child: TextFormField(
                              textInputAction: TextInputAction.done,
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final minutes = int.tryParse(value);
                                if (minutes != null &&
                                    minutes >= 0 &&
                                    minutes <= 60) {
                                  setState(() {
                                    beforeSleepTime = int.tryParse(value) ?? 14;
                                  });
                                  _changeBeforeSleepTime(minutes);
                                  generateTimeList();
                                }
                              },
                              controller: _beforeSleepController,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 24.spMin),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      //тестовое уведомление
                      onPressed: () async {
                        await NotificationsService.showTestNotification();
                      },
                      child: Text("Тестовое уведомление"),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 60
                          : 20,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class BigCard extends StatelessWidget {
  const BigCard({super.key, required TimeOfDay selectedTime})
    : _selectedTime = selectedTime;

  final TimeOfDay _selectedTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: EdgeInsets.all(15.spMin),
        child: Text(
          "${_selectedTime.hour.toString().padLeft(2, '0')} : ${_selectedTime.minute.toString().padLeft(2, '0')}",
          style: TextStyle(fontSize: 72.sp, color: theme.colorScheme.onPrimary),
        ),
      ),
    );
  }
}

class NotificationHelper {
  static String formatNotificationTimeShort(DateTime date) {
    return DateFormat('dd.MM в HH:mm', 'ru_RU').format(date);
  }

  static String formatNotificationHHmm(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  static String datesSchedule(List<int> days, DateTime notificationTime) {
    Map<int, String> daysMap = {
      1: "Пн",
      2: "Вт",
      3: "Ср",
      4: "Чт",
      5: "Пт",
      6: "Сб",
      7: "Вс",
    };

    if (days.isEmpty) {
      final now = DateTime.now();
      final todayNotification = DateTime(
        now.year,
        now.month,
        now.day,
        notificationTime.hour,
        notificationTime.minute,
      );
      final retString = !now.isBefore(todayNotification)
          ? "Завтра: ${now.add(Duration(days: 1)).day}"
          : "Сегодня: ${DateTime.now().day}";
      return retString;
    } else if (days.length == 7) {
      return "Ежедневно";
    } else {
      return "Кажд. ${days.map((index) => daysMap[index]!).join(", ")}";
    }
  }

  static List<int> formatNotificationsList(Map<String, dynamic> list) {
    return (list['days'] as List?)?.map((e) => e as int).toList() ?? [];
  }
}

class NotificationSettings extends StatefulWidget {
  final int id;
  final Map<String, dynamic> notification;
  final int pageNum;

  const NotificationSettings({
    super.key,
    required this.id,
    required this.notification,
    required this.pageNum,
  });

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  late DateTime time;
  List<String> daysOfWeek = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];
  List<int> selectedDays = [];

  @override
  void initState() {
    super.initState();
    time = DateTime.parse(widget.notification['time']);
    selectedDays =
        (widget.notification['days'] as List?)?.map((e) => e as int).toList() ??
        [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColorLight,
      body: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          children: [
            SizedBox(height: 80.h),
            Center(
              child: Card(
                color: Theme.of(context).colorScheme.primary,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    NotificationHelper.formatNotificationHHmm(
                      DateTime.parse(widget.notification['time']),
                    ).toString(),
                    style: TextStyle(
                      fontSize: 72.sp,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 15.h),
            Text(
              NotificationHelper.datesSchedule(selectedDays, time),
              style: TextStyle(
                fontSize: 19.sp,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 10.h),
            Transform.scale(
              scale: 0.8,
              child: Wrap(
                children: List.generate(7, (index) {
                  return ChoiceChip(
                    shape: CircleBorder(),
                    showCheckmark: false,
                    label: Text(
                      daysOfWeek[index],
                      style: TextStyle(fontSize: 14.sp),
                    ),
                    selected: selectedDays.contains(index + 1),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedDays.add(index + 1);
                        } else {
                          selectedDays.remove(index + 1);
                        }
                      });
                    },
                  );
                }),
              ),
            ),
            Spacer(),
            Row(
              children: [
                SizedBox(width: 20.w),
                ElevatedButton(
                  onPressed: () {
                    if (widget.pageNum == 0) {
                      Navigator.of(context).pop('cancel');
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  child: widget.pageNum == 0
                      ? Text("Удалить", style: TextStyle(fontSize: 20.sp))
                      : Text("Отмена", style: TextStyle(fontSize: 20.sp)),
                ),
                Spacer(),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop({'days': selectedDays});
                  },
                  child: Text("Сохранить", style: TextStyle(fontSize: 20.sp)),
                ),
                SizedBox(width: 20.w),
              ],
            ),
            SizedBox(height: 75.h),
          ],
        ),
      ),
    );
  }
}
