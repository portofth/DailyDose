import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart'; // Importante para Android 14+
import '../services/notification_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  bool _checking = false;

  final List<PermissionStep> _steps = [
    PermissionStep(
      permission: Permission.notification,
      title: "Vamos ativar os Lembretes",
      description: "Para que o DailyDose te avise na hora do remédio, precisamos da sua permissão para enviar notificações.",
      icon: Icons.notifications_active,
      color: Colors.lightBlue, 
    ),
    PermissionStep(
      permission: Permission.scheduleExactAlarm, // CRÍTICO NO ANDROID 14+
      title: "Pontualidade é tudo",
      description: "O Android 14+ bloqueia alarmes por padrão. Toque abaixo, procure 'Alarmes e Lembretes' e permita o DailyDose.",
      icon: Icons.alarm_on,
      color: Colors.orange,
    ),
    PermissionStep(
      permission: Permission.systemAlertWindow,
      title: "Tela Cheia",
      description: "Para o alarme aparecer sobre outros apps quando o celular estiver bloqueado.",
      icon: Icons.layers,
      color: Colors.lightBlueAccent, 
    ),
    PermissionStep(
      permission: Permission.ignoreBatteryOptimizations,
      title: "Sem atrasos",
      description: "O Android tenta desligar o app para economizar bateria. Precisamos que você diga 'Não Otimizar' ou 'Permitir uso irrestrito'.",
      icon: Icons.battery_alert,
      color: Colors.green, 
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Para detectar quando volta das configs
    _verificarStatusPassoAtual();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quando o usuário volta das configurações do Android, checa se ele ativou
    if (state == AppLifecycleState.resumed) {
      _verificarStatusPassoAtual();
    }
  }

  Future<void> _verificarStatusPassoAtual() async {
    if (!mounted) return;
    setState(() => _checking = true);
    
    final step = _steps[_currentStep];
    
    // Verificação especial para Alarmes no Android 12+
    PermissionStatus status;
    if (step.permission == Permission.scheduleExactAlarm && Platform.isAndroid) {
      // O permission_handler às vezes falha ao checar essa específica, 
      // mas vamos confiar no status dele por enquanto.
      status = await step.permission.status;
    } else {
      status = await step.permission.status;
    }

    if (status.isGranted) {
      _avancarPasso();
    }
    
    if (mounted) setState(() => _checking = false);
  }

  void _avancarPasso() {
    if (_currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
      });
      // Verifica o próximo passo imediatamente (caso já tenha sido concedido)
      _verificarStatusPassoAtual();
    } else {
      _finalizarConfiguracao();
    }
  }

  Future<void> _finalizarConfiguracao() async {
    final notificationService = NotificationService();
    await notificationService.markPermissionsConfigured();

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _solicitarPermissao() async {
    final step = _steps[_currentStep];
    
    // --- TRATAMENTO ESPECIAL PARA ALARME EXATO (ANDROID 13/14/15) ---
    if (step.permission == Permission.scheduleExactAlarm) {
        // No Android 14+, .request() retorna negado na hora. 
        // Temos que abrir a tela de configurações específica.
        if (Platform.isAndroid) {
           await const AndroidIntent(
             action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
           ).launch();
        }
        return;
    }
    // ---------------------------------------------------------------

    // --- TRATAMENTO PARA OUTRAS PERMISSÕES ---
    var status = await step.permission.status;

    if (status.isPermanentlyDenied) {
      if (mounted) _mostrarDialogoConfiguracoesManual();
      return;
    }

    final result = await step.permission.request();

    if (result.isGranted) {
      _avancarPasso();
    } else {
      if (mounted) {
         // Se for bateria ou overlay, muitas vezes vai direto pra negado permanente
         if (step.permission == Permission.ignoreBatteryOptimizations || 
             step.permission == Permission.systemAlertWindow) {
             _mostrarDialogoConfiguracoesManual();
         } else if (status.isPermanentlyDenied) {
             _mostrarDialogoConfiguracoesManual();
         } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Toque em 'Conceder' para continuar.")),
            );
         }
      }
    }
  }

  void _mostrarDialogoConfiguracoesManual() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ação Necessária"),
        content: const Text(
          "O Android bloqueou o pedido automático.\n\n"
          "Toque em 'Abrir Configurações' e ative a permissão manualmente para o DailyDose."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text("Abrir Configurações"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];
    final totalSteps = _steps.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Configuração ${ _currentStep + 1} de $totalSteps"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.lightBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinearProgressIndicator(
              value: (_currentStep + 1) / totalSteps,
              backgroundColor: Colors.grey[100],
              color: step.color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(5),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: step.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: _checking 
                ? CircularProgressIndicator(color: step.color)
                : Icon(step.icon, size: 80, color: step.color),
            ),
            const SizedBox(height: 30),
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.grey[800]
              ),
            ),
            const SizedBox(height: 16),
            Text(
              step.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16, 
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _solicitarPermissao,
                style: ElevatedButton.styleFrom(
                  backgroundColor: step.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 3,
                ),
                child: const Text(
                  "CONCEDER / ATIVAR",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }


}

class PermissionStep {
  final Permission permission;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  PermissionStep({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}