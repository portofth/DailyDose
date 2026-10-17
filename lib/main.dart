import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/remedio_service.dart';
import 'screens/home_screen.dart';
import 'screens/alarm_screen.dart';
import 'screens/permission_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try { await BackgroundService.init(); } catch (e) { print("Erro Bg: $e"); }
  try { await NotificationService().init(); } catch (e) { print("Erro Notif: $e"); }

  // VERIFICAÇÕES DE INICIALIZAÇÃO
  bool permissionsConfigured = false;

  try {
    final prefs = await SharedPreferences.getInstance();
    permissionsConfigured = prefs.getBool('permissions_configured') ?? false;
  } catch (e) {}

  // LÓGICA DE ROTA INICIAL (Simplificada)
  // 1. Se não configurou permissão -> Vai pra Permissão
  // 2. Se tá tudo certo -> Vai pra Home
  String rotaInicial;
  if (!permissionsConfigured) {
    rotaInicial = '/permissions';
  } else {
    rotaInicial = '/home';
  }

  runApp(DailyDoseApp(initialRoute: rotaInicial));
}

// LÓGICA PARA ABRIR A TELA VERMELHA
void _abrirAlarmePorHorario(String hora) async {
  try {
    final service = RemedioService();
    final notifService = NotificationService(); 

    // 1. VERIFICAÇÃO DE SEGURANÇA: Se já tomou, NÃO ABRE TELA E MATA O SOM
    if (await service.jaTomouHoje(hora)) {
      print("Alarme para $hora cancelado pois já foi tomado hoje.");
      await notifService.cancelarTudo(); 
      return;
    }

    final lista = await service.pegarRemediosDoHorario(hora);
    
    // 2. VERIFICAÇÃO DE LISTA VAZIA: Se não tem remédio ativo, MATA O SOM
    if (lista.isEmpty) {
      print("Alarme para $hora cancelado pois não há remédios ativos.");
      await notifService.cancelarTudo(); 
      return;
    }

    // 3. Se passou, abre a tela
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (context) => AlarmScreen(listaRemedios: lista)),
      );
    }
  } catch (e) {
    print("Erro ao abrir alarme: $e");
  }
}

class DailyDoseApp extends StatefulWidget {
  final String initialRoute;

  const DailyDoseApp({super.key, required this.initialRoute});

  @override
  State<DailyDoseApp> createState() => _DailyDoseAppState();
}

class _DailyDoseAppState extends State<DailyDoseApp> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarAlarmePendente());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarAlarmePendente();
    }
  }

  Future<void> _verificarAlarmePendente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); 
      final horaDisparo = prefs.getString('alarme_ativo_hora');

      if (horaDisparo != null && horaDisparo.isNotEmpty) {
        print("🚨 APP ACORDOU COM ALARME PENDENTE: $horaDisparo");
        await prefs.remove('alarme_ativo_hora'); 
        _abrirAlarmePorHorario(horaDisparo);
      }
    } catch (e) {
      print("Erro verificando pendência: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DailyDose',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.lightBlue, 
        scaffoldBackgroundColor: const Color(0xFFF5F9FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.lightBlue,
          elevation: 1,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue, foregroundColor: Colors.white)
        ),
      ),
      initialRoute: widget.initialRoute,
      routes: {
        '/home': (context) => const HomeScreen(),
        '/permissions': (context) => const PermissionScreen(),
      },
    );
  }
}