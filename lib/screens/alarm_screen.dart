import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/remedio.dart';
import '../services/remedio_service.dart'; 
import '../services/notification_service.dart'; 

class AlarmScreen extends StatefulWidget {
  final List<Remedio> listaRemedios;

  const AlarmScreen({super.key, required this.listaRemedios});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> with WidgetsBindingObserver {
  final FlutterTts _flutterTts = FlutterTts();
  final RemedioService _remedioService = RemedioService();
  
  bool _tocando = true;
  int _indiceAtual = 0;
  bool _saindo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _configurarTTS();
    _loopVibracao(); // Motor de vibração
    _loopFala();     // Motor de voz
  }

  Future<void> _configurarTTS() async {
    await _flutterTts.setLanguage("pt-BR");
    await _flutterTts.setSpeechRate(0.5); 
    await _flutterTts.setVolume(1.0);
    // Importante: awaitSpeakCompletion pode travar o stop em alguns Androids, 
    // mas ajuda na fila de fala. Vamos manter mas proteger o stop.
    await _flutterTts.awaitSpeakCompletion(true);
  }

  // --- MOTOR 1: VIBRAÇÃO ---
  void _loopVibracao() async {
    while (_tocando && mounted && !_saindo) {
      if (!_saindo) {
        // Padrão de chamada urgente
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 500));
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 500));
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  // --- MOTOR 2: FALA INTELIGENTE ---
  void _loopFala() async {
    await Future.delayed(const Duration(seconds: 1)); 
    
    while (_tocando && mounted && !_saindo) {
      if (_indiceAtual >= widget.listaRemedios.length) break;

      Remedio remedioAtual = widget.listaRemedios[_indiceAtual];

      if (_tocando && !_saindo) {
        // Lógica visual e auditiva para Colírio
        String acao = remedioAtual.tipo == 'colirio' ? "aplicar o colírio" : "tomar";
        String fala = "Hora de $acao: ${remedioAtual.nome}.";
        
        if (remedioAtual.dose.isNotEmpty) {
          fala += " Dose: ${remedioAtual.dose}";
        }
        
        try {
          await _flutterTts.speak(fala);
        } catch (e) {
          print("Erro TTS: $e"); // Ignora erro de fala para não travar
        }
      }
      
      if (_tocando && !_saindo) {
         if (_indiceAtual < widget.listaRemedios.length - 1) {
             await Future.delayed(const Duration(seconds: 1));
             try { await _flutterTts.speak("Ainda tem mais remédios."); } catch(e){}
         }
      }

      if (_tocando && !_saindo) await Future.delayed(const Duration(seconds: 3));
    }
  }

  // --- FUNÇÃO DO BOTÃO VERDE (BLINDADA) ---
  void _proximoOuFinalizar() async {
    // 1. Evita duplo clique
    if (_saindo) return;

    // 2. Para tudo imediatamente (visualmente)
    setState(() => _tocando = false);

    // 3. Tenta desligar sons e vibrações do sistema (com proteção contra erro)
    try {
      await NotificationService().cancelarTudo(); 
    } catch (e) {
      print("Erro ao cancelar notificação: $e");
    }

    try {
      await _flutterTts.stop();
    } catch (e) {
      print("Erro ao parar voz: $e");
    }

    // 4. Lógica de Navegação/Conclusão
    if (_indiceAtual < widget.listaRemedios.length - 1) {
      // Tem mais remédios na lista
      setState(() {
        _indiceAtual++;
        _tocando = true; // Reinicia loops para o próximo
      });
      _loopVibracao();
      _loopFala();
    } else {
      // Acabou a lista -> Salvar e Sair
      setState(() => _saindo = true);
      
      // Salva no banco
      if (widget.listaRemedios.isNotEmpty) {
        final horario = widget.listaRemedios.first.hora;
        await _remedioService.marcarComoTomadoHoje(horario);
      }

      // Feedback visual
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registrado!"), backgroundColor: Colors.green),
        );
      }

      // Aguarda um instante e fecha a tela
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        // Força a navegação para Home, limpando a tela de alarme
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  }

  @override
  void dispose() {
    _tocando = false;
    _saindo = true;
    _flutterTts.stop();
    // Tenta cancelar notificações ao fechar a tela também
    try { NotificationService().cancelarTudo(); } catch(e){}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.listaRemedios.isEmpty) return const SizedBox();

    final remedioAtual = widget.listaRemedios[_indiceAtual];
    final total = widget.listaRemedios.length;
    
    // Configuração Visual (Ícones e Cores)
    final bool isColirio = remedioAtual.tipo == 'colirio';
    final IconData iconData = isColirio ? Icons.visibility : Icons.notifications_active;
    final Color iconColor = isColirio ? Colors.teal : Colors.red;
    final String tituloTexto = isColirio ? "HORA DO COLÍRIO" : "HORA DO REMÉDIO";

    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _proximoOuFinalizar(); // Botão voltar do celular também confirma
      },
      child: Scaffold(
        backgroundColor: _saindo ? Colors.grey[200] : (isColirio ? Colors.teal[50] : Colors.red[50]),
        body: SafeArea(
          child: IgnorePointer(
            ignoring: _saindo,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Medicamento ${_indiceAtual + 1} de $total",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                ),
                const SizedBox(height: 20),
                
                // Ícone Animado (Piscando logicamente pela troca de remédios)
                Icon(iconData, size: 100, color: iconColor),
                
                const SizedBox(height: 20),
                Text(
                  tituloTexto,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: iconColor),
                ),
                const SizedBox(height: 20),
                
                // Card do Nome
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: iconColor, width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      Text(
                        remedioAtual.nome.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                      if (remedioAtual.dose.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          remedioAtual.dose,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, color: Colors.black54),
                        ),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                
                // Botão de Ação
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: SizedBox(
                    height: 90, 
                    child: ElevatedButton.icon(
                      onPressed: _proximoOuFinalizar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _saindo ? Colors.grey : (isColirio ? Colors.teal : Colors.green),
                        foregroundColor: Colors.white,
                        elevation: 10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: _saindo 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle, size: 45),
                      label: Text(
                        _saindo 
                          ? "SALVANDO..." 
                          : (_indiceAtual < total - 1 ? "PRÓXIMO >>" : (isColirio ? "JÁ APLIQUEI" : "JÁ TOMEI")), 
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}