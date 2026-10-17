import 'dart:typed_data'; 
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remedio_service.dart'; // <--- IMPORTANTE: Importar o serviço

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void dispararAlarmeGlobal(int id) async {
  WidgetsFlutterBinding.ensureInitialized();
  print("BACKGROUND: TENTATIVA DE DISPARO ID $id");

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); 
    
    bool deveTocarSom = true;

    // --- LÓGICA DE TOLERÂNCIA (10 MINUTOS) ---
    final targetMillis = prefs.getInt('alarme_target_$id');
    if (targetMillis != null) {
      final dataAgendada = DateTime.fromMillisecondsSinceEpoch(targetMillis);
      final agora = DateTime.now();
      final diferencaMinutos = agora.difference(dataAgendada).inMinutes;

      // Se passou mais de 10 minutos, silencia e não mostra a tela de alerta
      if (diferencaMinutos.abs() > 10) { 
        print("BACKGROUND: Atraso de $diferencaMinutos min. Modo silencioso.");
        deveTocarSom = false; 
      }
    }

    final horario = prefs.getString('alarme_horario_$id') ?? "Hora do Remédio";

    // --- REAGENDAMENTO AUTOMÁTICO (NOVO) ---
    // Isso garante que o próximo alarme seja agendado INDEPENDENTE de abrir o app
    try {
      print("BACKGROUND: Calculando próximo alarme para $horario...");
      final remedioService = RemedioService();
      // Calcula quando será a próxima vez (amanhã ou depois)
      final segundos = await remedioService.calcularProximoIntervaloSegundos(horario);
      
      if (segundos != null) {
        print("BACKGROUND: Próximo alarme reagendado para daqui a $segundos segundos.");
        // Agenda o próximo ciclo agora mesmo!
        await BackgroundService.agendar(id, horario, segundos);
      } else {
        print("BACKGROUND: Nenhum agendamento futuro encontrado para $horario.");
      }
    } catch (e) {
      print("ERRO REAGENDAMENTO BACKGROUND: $e");
    }
    // ----------------------------------------

    if (deveTocarSom) {
      // Se vai tocar som, avisa o main.dart para mostrar a tela vermelha
      await prefs.setString('alarme_ativo_hora', horario);
    } else {
      // Se estiver atrasado, limpa para não mostrar a tela vermelha
      await prefs.remove('alarme_ativo_hora');
    }

    if (deveTocarSom) {
      // Inicializa e dispara notificação...
      const AndroidInitializationSettings initializationSettingsAndroid = 
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        'med_alarm_chamada_v2', 
        'Alarme de Remédio',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        vibrationPattern: Int64List.fromList([0, 4000, 500, 4000, 500, 4000, 500, 4000, 500, 4000, 500]),
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await flutterLocalNotificationsPlugin.show(
        id,
        'HORA DO REMÉDIO: $horario',
        'Toque para abrir o aplicativo',
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true, 
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            ongoing: false,       
            autoCancel: true,     
            visibility: NotificationVisibility.public,
            additionalFlags: Int32List.fromList([4]), 
            vibrationPattern: Int64List.fromList([0, 4000, 500, 4000, 500, 4000, 500, 4000, 500, 4000, 500]),
            actions: [
              const AndroidNotificationAction('stop_action', 'PARAR', showsUserInterface: true),
            ]
          ),
        ),
        payload: horario,
      );
    }

    // Abertura do App (Continua como backup e para acordar a CPU)
    const String seuPackageName = 'com.example.alarmeremedio'; 

    final intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: seuPackageName, 
      componentName: '$seuPackageName.MainActivity', 
      category: 'android.intent.category.LAUNCHER',
      flags: [
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_ACTIVITY_NO_USER_ACTION,
        Flag.FLAG_ACTIVITY_SINGLE_TOP,
        Flag.FLAG_ACTIVITY_CLEAR_TOP,
        Flag.FLAG_RECEIVER_FOREGROUND, 
      ],
    );
    await intent.launch();
    
  } catch (e) {
    print("ERRO BACKGROUND: $e");
  }
}

class BackgroundService {
  static Future<void> init() async {
    await AndroidAlarmManager.initialize();
  }

  static Future<void> agendar(int id, String horario, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarme_horario_$id', horario);
    
    final dataAlvo = DateTime.now().add(Duration(seconds: seconds));
    await prefs.setInt('alarme_target_$id', dataAlvo.millisecondsSinceEpoch);

    int tempo = seconds < 5 ? 5 : seconds;

    await AndroidAlarmManager.oneShot(
      Duration(seconds: tempo),
      id,
      dispararAlarmeGlobal, 
      exact: true,
      wakeup: true,
      alarmClock: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true, 
    );
  }

  static Future<void> cancelar(int id) async {
    print("BACKGROUND: Cancelando alarme ID $id");
    await AndroidAlarmManager.cancel(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarme_horario_$id');
    await prefs.remove('alarme_target_$id');
  }
}