import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; 
import '../services/remedio_service.dart';
import '../screens/alarm_screen.dart';
import 'background_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    try { tz.setLocalLocation(tz.getLocation('America/Sao_Paulo')); } catch (e) { tz.setLocalLocation(tz.UTC); }

   const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Se clicar em parar ou no corpo da notificação, abre a tela
        if (response.payload != null) {
          _abrirTelaDeAlarme(response.payload!);
        }
      },
    );
    await _createNotificationChannels();
  }

  void _abrirTelaDeAlarme(String hora) async {
    // Cancela o som da notificação ao abrir
    await cancelarTudo();
    
    final service = RemedioService();
    if (await service.jaTomouHoje(hora)) return;
    final lista = await service.pegarRemediosDoHorario(hora);
    if (lista.isNotEmpty) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => AlarmScreen(listaRemedios: lista)));
    }
  }

  Future<void> _createNotificationChannels() async {
    final AndroidNotificationChannel channelAlarm = AndroidNotificationChannel(
      'med_alarm_chamada_v2', 
      'Alarme de Remédio',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      vibrationPattern: Int64List.fromList([0, 4000, 500, 4000, 500, 4000, 500, 4000, 500, 4000, 500]),
    );
    await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channelAlarm);
  }

  Future<void> cancelarTudo() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> scheduleAlarmSequence({required int baseId, String? title, String? body, required String payloadHora, required int secondsFromNow}) async {
    await BackgroundService.agendar(baseId, payloadHora, secondsFromNow);
  }

  // --- NOVA FUNÇÃO DE CANCELAMENTO ESPECÍFICO ---
  Future<void> cancelarAlarmeEspecifico(int baseId) async {
    await BackgroundService.cancelar(baseId);
  }

  // --- PERMISSÕES (Mantido igual) ---
  Future<Map<String, dynamic>> verificarStatusGeral() async {
    final notif = await Permission.notification.isGranted;
    final alarm = await Permission.scheduleExactAlarm.isGranted;
    final overlay = await Permission.systemAlertWindow.isGranted;
    final bateria = await Permission.ignoreBatteryOptimizations.isGranted;
    return {'notif': notif, 'alarm': alarm, 'overlay': overlay, 'bateria': bateria, 'tudo_ok': notif && alarm && overlay && bateria};
  }
  Future<void> solicitarNotificacao() async => await Permission.notification.request();
  Future<void> solicitarAlarmeExato() async => await Permission.scheduleExactAlarm.request();
  Future<void> solicitarOverlay() async => await Permission.systemAlertWindow.request();
  Future<void> solicitarIgnorarBateria() async => await Permission.ignoreBatteryOptimizations.request();
  Future<bool> arePermissionsConfigured() async { final prefs = await SharedPreferences.getInstance(); return prefs.getBool('permissions_configured') ?? false; }
  Future<void> markPermissionsConfigured() async { final prefs = await SharedPreferences.getInstance(); await prefs.setBool('permissions_configured', true); }
}