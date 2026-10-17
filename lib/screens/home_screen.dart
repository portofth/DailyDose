import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/remedio.dart';
import '../services/remedio_service.dart';
import '../services/notification_service.dart';
import 'alarm_screen.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final RemedioService _remedioService = RemedioService();
  final ScrollController _scrollController = ScrollController();
  
  Map<String, List<Remedio>> _remediosAgrupados = {};
  String? _proximoHorarioDestaque; 
  bool _permissoesOk = true;
  Timer? _timerRelogio;
  
  // Travas e Estados
  bool _navegandoParaAlarme = false;
  String? _ultimoHorarioDisparado;
  bool _carregando = true; // Controla o Spinner inicial

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _inicializar();

    // VIGIA (Rodando a cada 5s para monitorar o horário)
    _timerRelogio = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && !_navegandoParaAlarme) {
        _atualizarDestaqueVisual();
        _vigiarHorarioAtual(); 
      }
    });
  }

  // --- INICIALIZAÇÃO ---
  void _inicializar() async {
    _checarPermissoes();
    // Carrega os dados do banco (que já vem com a lista do Vô Tarcísio se for novo)
    await _carregarDados(agendar: true);
    
    if (mounted) {
      setState(() => _carregando = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checarPermissoes();
      if (!_carregando) _carregarDados(agendar: false); 
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerRelogio?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // --- LÓGICA DO VIGIA (Dispara a tela de alarme) ---
  void _vigiarHorarioAtual() async {
    final agora = DateTime.now();
    final horaFormatada = DateFormat('HH:mm').format(agora);

    if (_ultimoHorarioDisparado == horaFormatada) return;

    if (_remediosAgrupados.containsKey(horaFormatada)) {
      bool jaTomou = await _remedioService.jaTomouHoje(horaFormatada);
      
      if (!jaTomou) {
        final lista = _remediosAgrupados[horaFormatada]!;
        
        final ativos = lista.where((r) => 
            !r.isSuspenso && 
            !r.isFinalizado && 
            _remedioService.deveTomarNestaData(r, agora)
        ).toList();

        if (ativos.isNotEmpty) {
          setState(() {
            _navegandoParaAlarme = true;
            _ultimoHorarioDisparado = horaFormatada;
          });
          
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AlarmScreen(listaRemedios: ativos)),
          );

          if (mounted) {
            setState(() => _navegandoParaAlarme = false);
            _carregarDados(agendar: false);
          }
        }
      }
    }
  }

  // --- LEITURA DE DADOS ---
  Future<void> _carregarDados({bool agendar = false}) async {
    final lista = await _remedioService.carregarRemedios();
    
    Map<String, List<Remedio>> grupo = {};
    for (var r in lista) {
      if (!grupo.containsKey(r.hora)) grupo[r.hora] = [];
      grupo[r.hora]!.add(r);
    }
    var chavesOrdenadas = grupo.keys.toList()..sort();
    Map<String, List<Remedio>> grupoOrdenado = { for (var k in chavesOrdenadas) k: grupo[k]! };

    if (mounted) {
      setState(() => _remediosAgrupados = grupoOrdenado);
      _atualizarDestaqueVisual(); 
      if (agendar) _agendarTodosAlarmes();
    }
  }

  void _atualizarDestaqueVisual() {
    if (_remediosAgrupados.isEmpty) return;
    final agora = DateTime.now();
    final agoraEmMinutos = agora.hour * 60 + agora.minute;
    
    String? proximoHorario;
    double offsetParaRolar = 0.0;
    bool encontrou = false;
    const double alturaCabecalho = 60.0; 
    const double alturaCard = 100.0; 
    
    for (var entry in _remediosAgrupados.entries) {
      String horaStr = entry.key;
      int hora = int.parse(horaStr.split(':')[0]);
      int minuto = int.parse(horaStr.split(':')[1]);
      int horarioEmMinutos = hora * 60 + minuto;

      if (!encontrou && horarioEmMinutos >= agoraEmMinutos) {
        proximoHorario = horaStr;
        encontrou = true;
      }
      if (!encontrou) {
        offsetParaRolar += alturaCabecalho + (entry.value.length * alturaCard);
      }
    }
    if (proximoHorario == null && _remediosAgrupados.isNotEmpty) {
      proximoHorario = _remediosAgrupados.keys.first;
      offsetParaRolar = 0.0;
    }
    if (mounted) setState(() => _proximoHorarioDestaque = proximoHorario);
    
    if (_scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _scrollController.hasClients) {
                _scrollController.animateTo(offsetParaRolar, duration: const Duration(seconds: 1), curve: Curves.easeInOut);
            }
        });
    }
  }

  // --- AGENDAMENTO NO ANDROID (BACKGROUND) ---
  void _agendarTodosAlarmes() {
    _remediosAgrupados.forEach((hora, listaTodos) async {
      
      final remediosAtivos = listaTodos.where((r) => !r.isSuspenso && !r.isFinalizado).toList();
      
      if (remediosAtivos.isNotEmpty) {
        final segundosAteOProximo = _calcularSegundosAteProximaOcorrencia(hora, remediosAtivos);
        
        if (segundosAteOProximo != null && segundosAteOProximo > 10) {
            final idAlarme = int.parse(hora.replaceAll(':', ''));
            final nomes = remediosAtivos.map((e) => e.nome).join(", ");
            
            // Agenda com tolerância zero (lógica está no background_service)
            NotificationService().scheduleAlarmSequence(
              baseId: idAlarme,
              title: 'HORA DO REMÉDIO',
              body: 'Tomar: $nomes',
              payloadHora: hora,
              secondsFromNow: segundosAteOProximo,
            );
        }
      }
    });
  }

  int? _calcularSegundosAteProximaOcorrencia(String horaString, List<Remedio> remedios) {
    final agora = DateTime.now();
    final partes = horaString.split(':');
    final hora = int.parse(partes[0]);
    final minuto = int.parse(partes[1]);

    for (int i = 0; i <= 30; i++) {
      final dataTeste = agora.add(Duration(days: i));
      final dataAlarmeTeste = DateTime(dataTeste.year, dataTeste.month, dataTeste.day, hora, minuto, 0);

      if (dataAlarmeTeste.isBefore(agora)) continue;

      bool temRemedioNesseDia = remedios.any((r) => _remedioService.deveTomarNestaData(r, dataTeste));

      if (temRemedioNesseDia) {
        return dataAlarmeTeste.difference(agora).inSeconds;
      }
    }
    return null; 
  }

  // --- UI E PERMISSÕES ---

void _checarPermissoes() async {
    try {
      final status = await NotificationService().verificarStatusGeral();
      if (mounted) {
        setState(() => _permissoesOk = status['tudo_ok'] ?? true);
        
        
        // Se a permissão crítica de Alarme Exato foi revogada, força a tela de permissão
        if (status['alarm'] == false) {
           Navigator.of(context).pushReplacementNamed('/permissions');
        }
       
      }
    } catch (e) { 
      if (mounted) setState(() => _permissoesOk = true); 
    }
  }
  void _abrirModalCorrecao() async {
    final service = NotificationService();
    final status = await service.verificarStatusGeral();
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
            void atualizarLocal() async { 
              final novoStatus = await service.verificarStatusGeral(); 
              setModalState(() {}); 
              _checarPermissoes(); 
              if (novoStatus['tudo_ok'] == true) Navigator.pop(context); 
            }
            
            return Padding(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Configurações", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
                  const SizedBox(height: 10),
                  
                  Container(
                    width: double.infinity, 
                    margin: const EdgeInsets.only(bottom: 20),
                    child: ElevatedButton.icon(
                      onPressed: () { 
                        _agendarTodosAlarmes(); 
                        Navigator.pop(context); 
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reagendado!"), backgroundColor: Colors.green)); 
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text("FORÇAR REAGENDAMENTO"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white)
                    )
                  ),
                  
                  _itemPermissao(titulo: "Notificações", descricao: "Avisos", ok: status['notif'] ?? false, onTap: () async { await service.solicitarNotificacao(); atualizarLocal(); }),
                  _itemPermissao(titulo: "Alarmes Exatos", descricao: "Pontualidade", ok: status['alarm'] ?? false, onTap: () async { await service.solicitarAlarmeExato(); atualizarLocal(); }),
                  _itemPermissao(titulo: "Sobreposição", descricao: "Tela cheia", ok: status['overlay'] ?? false, onTap: () async { await service.solicitarOverlay(); atualizarLocal(); }),
                  _itemPermissao(titulo: "Bateria", descricao: "Sem otimização", ok: status['bateria'] ?? false, onTap: () async { await service.solicitarIgnorarBateria(); atualizarLocal(); }),
                  
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar")))
                ]
              ),
            );
        });
      }
    );
  }

  Widget _itemPermissao({required String titulo, required String descricao, required bool ok, required VoidCallback onTap}) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: ok ? Colors.green[100] : Colors.red[100], child: Icon(ok ? Icons.check : Icons.close, color: ok ? Colors.green : Colors.red)),
      title: Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, decoration: ok ? TextDecoration.lineThrough : null)),
      subtitle: Text(descricao),
      trailing: ok ? null : ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue, foregroundColor: Colors.white), child: const Text("ATIVAR"))
    );
  }

  // --- SELETOR DE FREQUÊNCIA ---

  void _mostrarSeletorFrequencia({
    required String tipoAtual,
    List<int>? diasAtuais,
    int? intervaloAtual,
    required Function(String, List<int>?, int?) onConfirmar
  }) {
    String tipoSelecionado = tipoAtual;
    List<int> diasSelecionados = diasAtuais ?? [];
    int? intervaloSelecionado = intervaloAtual;
    final intervaloController = TextEditingController(text: intervaloAtual?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20, left: 20, right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Frequência", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
                  const SizedBox(height: 10),
                  
                  RadioListTile<String>(title: const Text("Todos os dias"), value: 'todos', groupValue: tipoSelecionado, onChanged: (v) => setSheetState(() => tipoSelecionado = v!)),
                  RadioListTile<String>(title: const Text("Dias da semana específicos"), value: 'semanal', groupValue: tipoSelecionado, onChanged: (v) => setSheetState(() => tipoSelecionado = v!)),
                  
                  if (tipoSelecionado == 'semanal')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (int i = 1; i <= 7; i++)
                            FilterChip(
                              label: Text(["S", "T", "Q", "Q", "S", "S", "D"][i-1]),
                              selected: diasSelecionados.contains(i),
                              onSelected: (selected) {
                                setSheetState(() {
                                  selected ? diasSelecionados.add(i) : diasSelecionados.remove(i);
                                });
                              },
                              showCheckmark: false,
                              selectedColor: Colors.lightBlue,
                              labelStyle: TextStyle(color: diasSelecionados.contains(i) ? Colors.white : Colors.black),
                            )
                        ],
                      ),
                    ),

                  RadioListTile<String>(title: const Text("Intervalo de dias"), value: 'intervalo', groupValue: tipoSelecionado, onChanged: (v) => setSheetState(() => tipoSelecionado = v!)),
                  
                  if (tipoSelecionado == 'intervalo')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: intervaloController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "A cada quantos dias?", hintText: "Ex: 2 (Dia sim, dia não)", prefixIcon: Icon(Icons.repeat)),
                        onChanged: (v) => intervaloSelecionado = int.tryParse(v),
                      ),
                    ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (tipoSelecionado == 'semanal' && diasSelecionados.isEmpty) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selecione pelo menos um dia.")));
                           return;
                        }
                        if (tipoSelecionado == 'intervalo' && (intervaloSelecionado == null || intervaloSelecionado! < 2)) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Intervalo inválido. Mínimo 2 dias.")));
                           return;
                        }
                        onConfirmar(tipoSelecionado, diasSelecionados, intervaloSelecionado);
                        Navigator.pop(context);
                      },
                      child: const Text("CONFIRMAR"),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  // --- SELETOR DE DURAÇÃO ---
  void _mostrarSeletorDuracao(Function(DateTime?) onSelecionado) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (context) {
        return Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text("Duração do Tratamento", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.lightBlue))),
          ListTile(leading: const Icon(Icons.all_inclusive, color: Colors.green), title: const Text("Uso Contínuo (Sem data final)"), onTap: () { onSelecionado(null); Navigator.pop(context); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.calendar_view_week, color: Colors.blue), title: const Text("Por 7 dias (1 semana)"), onTap: () { onSelecionado(DateTime.now().add(const Duration(days: 7))); Navigator.pop(context); }),
          ListTile(leading: const Icon(Icons.date_range, color: Colors.blue), title: const Text("Por 14 dias (2 semanas)"), onTap: () { onSelecionado(DateTime.now().add(const Duration(days: 14))); Navigator.pop(context); }),
          ListTile(leading: const Icon(Icons.calendar_month, color: Colors.blue), title: const Text("Por 1 mês (30 dias)"), onTap: () { onSelecionado(DateTime.now().add(const Duration(days: 30))); Navigator.pop(context); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.edit_calendar, color: Colors.orange), title: const Text("Personalizado..."), onTap: () async { Navigator.pop(context); final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650))); if(d != null) onSelecionado(d); })
        ]));
    });
  }

  // --- DIÁLOGO PRINCIPAL (NOVO/EDITAR) ---
  void _mostrarDialogo({Remedio? remedioExistente}) {
    final nomeController = TextEditingController(text: remedioExistente?.nome ?? '');
    final doseController = TextEditingController(text: remedioExistente?.dose ?? '');
    
    TimeOfDay horarioSelecionado = remedioExistente != null 
        ? TimeOfDay(hour: int.parse(remedioExistente.hora.split(':')[0]), minute: int.parse(remedioExistente.hora.split(':')[1])) 
        : TimeOfDay.now();
        
    DateTime? dataTerminoTemp = remedioExistente?.dataTermino != null 
        ? DateTime.fromMillisecondsSinceEpoch(remedioExistente!.dataTermino!) 
        : null;

    String freqTipo = remedioExistente?.frequenciaTipo ?? 'todos';
    List<int> freqDias = remedioExistente?.diasSemana != null ? List.from(remedioExistente!.diasSemana!) : [];
    int? freqIntervalo = remedioExistente?.intervaloDias;
    
    String tipoRemedio = remedioExistente?.tipo ?? 'geral';

    String getTextoFrequencia() {
      if (freqTipo == 'todos') return "Todos os dias";
      if (freqTipo == 'intervalo') return "A cada $freqIntervalo dias";
      if (freqTipo == 'semanal') {
         if (freqDias.isEmpty) return "Selecione dias...";
         final diasSigla = freqDias.map((d) => ["S","T","Q","Q","S","S","D"][d-1]).join(", ");
         return "Semanal: $diasSigla";
      }
      return "Selecionar...";
    }

    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(remedioExistente == null ? "Novo Remédio" : "Editar Remédio", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: nomeController, decoration: const InputDecoration(labelText: "Nome do Remédio", prefixIcon: Icon(Icons.medication_liquid), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))))),
                  const SizedBox(height: 15),
                  TextField(controller: doseController, decoration: const InputDecoration(labelText: "Dose (ex: 1 cp, 2 gotas)", prefixIcon: Icon(Icons.scale), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))))),
                  const SizedBox(height: 20),
                  
                  // --- SELETOR DE TIPO (COM ÍCONES) ---
                  const Text("Tipo de Aplicação", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: Row(
                            children: const [
                              Icon(Icons.medication, size: 18, color: Colors.lightBlue),
                              SizedBox(width: 8),
                              Text("Comum", style: TextStyle(fontSize: 14)),
                            ],
                          ),
                          value: 'geral',
                          groupValue: tipoRemedio,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.lightBlue,
                          onChanged: (val) => setDialogState(() => tipoRemedio = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: Row(
                            children: const [
                              Icon(Icons.visibility, size: 18, color: Colors.teal),
                              SizedBox(width: 8),
                              Text("Colírio", style: TextStyle(fontSize: 14)),
                            ],
                          ),
                          value: 'colirio',
                          groupValue: tipoRemedio,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.lightBlue,
                          onChanged: (val) => setDialogState(() => tipoRemedio = val!),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
                    title: const Text("Horário"), 
                    subtitle: Text("${horarioSelecionado.hour.toString().padLeft(2, '0')}:${horarioSelecionado.minute.toString().padLeft(2, '0')}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                    leading: const Icon(Icons.access_time_filled, color: Colors.lightBlue), 
                    onTap: () async { 
                      final time = await showTimePicker(context: context, initialTime: horarioSelecionado, builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
                      if (time != null) setDialogState(() => horarioSelecionado = time); 
                    }
                  ),
                  const SizedBox(height: 10),

                  // BOTÃO DE FREQUÊNCIA
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
                    title: const Text("Frequência"),
                    subtitle: Text(getTextoFrequencia(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    leading: const Icon(Icons.repeat, color: Colors.lightBlue), 
                    onTap: () {
                      _mostrarSeletorFrequencia(
                        tipoAtual: freqTipo,
                        diasAtuais: freqDias,
                        intervaloAtual: freqIntervalo,
                        onConfirmar: (t, d, i) {
                           setDialogState(() {
                             freqTipo = t;
                             freqDias = d ?? [];
                             freqIntervalo = i;
                           });
                        }
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
                    title: const Text("Duração"), 
                    subtitle: Text(
                      dataTerminoTemp != null ? "Até ${DateFormat('dd/MM/yyyy').format(dataTerminoTemp!)}" : "Uso Contínuo (Sem fim)",
                      style: TextStyle(fontWeight: FontWeight.bold, color: dataTerminoTemp != null ? Colors.black87 : Colors.green)
                    ), 
                    leading: const Icon(Icons.calendar_month, color: Colors.lightBlue), 
                    onTap: () {
                      _mostrarSeletorDuracao((novaData) {
                        setDialogState(() => dataTerminoTemp = novaData);
                      });
                    }
                  )
              ])
            ), 
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))), 
              ElevatedButton(
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () { 
                  if (nomeController.text.isEmpty) return; 
                  _salvar(
                    id: remedioExistente?.id, 
                    nome: nomeController.text, 
                    dose: doseController.text, 
                    hora: horarioSelecionado, 
                    dataTermino: dataTerminoTemp,
                    freqTipo: freqTipo,
                    freqDias: freqDias,
                    freqIntervalo: freqIntervalo,
                    dataCriacao: remedioExistente?.dataCriacao,
                    tipo: tipoRemedio 
                  ); 
                  Navigator.pop(context); 
                }, 
                child: const Text("SALVAR")
              )
            ]
          );
    }));
  }

  // 3. MENU DE SUSPENSÃO
  void _mostrarOpcoesSuspensao(Remedio remedio) { 
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0), 
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            const Text("Suspender temporariamente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)), 
            const SizedBox(height: 20),
            _itemOpcao(Icons.calendar_view_week, "Por 1 semana", () => _aplicarSuspensao(remedio, 7)), 
            _itemOpcao(Icons.date_range, "Por 15 dias", () => _aplicarSuspensao(remedio, 15)),
            _itemOpcao(Icons.calendar_month, "Por 1 mês", () => _aplicarSuspensao(remedio, 30)),
            const Divider(),
            _itemOpcao(Icons.edit_calendar, "Escolher data de retorno...", () async {
                Navigator.pop(context);
                final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) _salvarSuspensaoManual(remedio, d);
            }),
          ]
        )
      )
    ); 
  }
  
  Widget _itemOpcao(IconData icon, String texto, VoidCallback onTap) { 
    return ListTile(leading: Icon(icon, color: Colors.lightBlue), title: Text(texto), onTap: onTap); 
  }

  // --- CRUD COM PROTEÇÃO CONTRA ALARMES FANTASMAS ---
  void _salvar({
      int? id, 
      required String nome, 
      required String dose, 
      required TimeOfDay hora, 
      DateTime? dataTermino,
      String freqTipo = 'todos',
      List<int>? freqDias,
      int? freqIntervalo,
      int? dataCriacao,
      String tipo = 'geral', 
    }) async {
      
    final horaFormatada = "${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}";
    final novoId = id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final criacao = dataCriacao ?? DateTime.now().millisecondsSinceEpoch;

    List<Remedio> listaAtual = [];
    _remediosAgrupados.values.forEach((l) => listaAtual.addAll(l));
    
    // LOGICA ANTI-FANTASMA (AO EDITAR)
    if (id != null) {
      final idx = listaAtual.indexWhere((r) => r.id == id);
      if (idx != -1) {
        Remedio antigo = listaAtual[idx];
        // Se mudou o horário, cancela o alarme antigo SE for o único
        if (antigo.hora != horaFormatada) {
           bool eraOUnico = listaAtual.where((r) => r.hora == antigo.hora && r.id != id).isEmpty;
           if (eraOUnico) {
             print("Removendo alarme antigo das ${antigo.hora}");
             final idAlarme = int.parse(antigo.hora.replaceAll(':', ''));
             await NotificationService().cancelarAlarmeEspecifico(idAlarme);
           }
        }
      }
    }

    final novoRemedio = Remedio(
      id: novoId, 
      nome: nome, 
      dose: dose, 
      hora: horaFormatada, 
      dataTermino: dataTermino?.millisecondsSinceEpoch,
      dataCriacao: criacao,
      frequenciaTipo: freqTipo,
      diasSemana: freqDias,
      intervaloDias: freqIntervalo,
      tipo: tipo,
    );

    if (id == null) {
      listaAtual.add(novoRemedio);
    } else {
      final idx = listaAtual.indexWhere((r) => r.id == id);
      if (idx != -1) {
        listaAtual[idx] = Remedio(
          id: novoId, 
          nome: nome, 
          dose: dose, 
          hora: horaFormatada, 
          dataTermino: dataTermino?.millisecondsSinceEpoch, 
          dataSuspensao: listaAtual[idx].dataSuspensao,
          dataCriacao: criacao,
          frequenciaTipo: freqTipo,
          diasSemana: freqDias,
          intervaloDias: freqIntervalo,
          tipo: tipo,
        );
      }
    }
    await _remedioService.salvarLista(listaAtual);
    _carregarDados(agendar: true);
  }

  void _confirmarExclusao(Remedio r) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Excluir?"), content: Text("Deseja apagar '${r.nome}'?"), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
        TextButton(onPressed: () { Navigator.pop(ctx); _deletar(r); }, child: const Text("EXCLUIR", style: TextStyle(color: Colors.red)))
      ]
    ));
  }

  // --- LOGICA ANTI-FANTASMA (AO DELETAR) ---
  void _deletar(Remedio remedioParaDeletar) async {
    List<Remedio> lista = []; 
    _remediosAgrupados.values.forEach((l) => lista.addAll(l));
    
    // Verifica se era o único nesse horário
    bool eraOUnico = lista.where((r) => r.hora == remedioParaDeletar.hora && r.id != remedioParaDeletar.id).isEmpty;
    
    if (eraOUnico) {
      print("Removendo alarme das ${remedioParaDeletar.hora} pois era o último remédio.");
      final idAlarme = int.parse(remedioParaDeletar.hora.replaceAll(':', ''));
      await NotificationService().cancelarAlarmeEspecifico(idAlarme);
    }

    lista.removeWhere((r) => r.id == remedioParaDeletar.id);
    await _remedioService.salvarLista(lista);
    _carregarDados(agendar: true);
  }

  void _aplicarSuspensao(Remedio r, int dias) { final data = DateTime.now().add(Duration(days: dias)); _salvarSuspensaoManual(r, data); Navigator.pop(context); }
  
  void _salvarSuspensaoManual(Remedio r, DateTime data) async { 
    final novo = Remedio(
      id: r.id, nome: r.nome, dose: r.dose, hora: r.hora, 
      dataSuspensao: data.millisecondsSinceEpoch, dataTermino: r.dataTermino,
      dataCriacao: r.dataCriacao, frequenciaTipo: r.frequenciaTipo, diasSemana: r.diasSemana, intervaloDias: r.intervaloDias,
      tipo: r.tipo 
    ); 
    _atualizar(novo); 
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Suspenso até ${DateFormat('dd/MM').format(data)}"))); 
  }
  
  void _retomarRemedio(Remedio r) { 
    final novo = Remedio(
      id: r.id, nome: r.nome, dose: r.dose, hora: r.hora, 
      dataSuspensao: null, dataTermino: r.dataTermino,
      dataCriacao: r.dataCriacao, frequenciaTipo: r.frequenciaTipo, diasSemana: r.diasSemana, intervaloDias: r.intervaloDias,
      tipo: r.tipo
    ); 
    _atualizar(novo); 
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tratamento retomado!"))); 
  }
  
  void _atualizar(Remedio n) async { List<Remedio> l = []; _remediosAgrupados.values.forEach((li) => l.addAll(li)); int i = l.indexWhere((item) => item.id == n.id); if(i!=-1) l[i]=n; await _remedioService.salvarLista(l); _carregarDados(agendar: true); }

  @override
  Widget build(BuildContext context) {
    
    // --- SPINNER DE CARREGAMENTO ---
    if (_carregando) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("DailyDose", style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true, actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _abrirModalCorrecao)]),
      body: Column(children: [
          if (!_permissoesOk) GestureDetector(onTap: _abrirModalCorrecao, child: Container(width: double.infinity, margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.orange[50], border: Border.all(color: Colors.orange), borderRadius: BorderRadius.circular(12)), child: const Text("⚠️ Configurar Permissões (Toque aqui)", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))),
          Expanded(child: _remediosAgrupados.isEmpty ? const Center(child: Text("Nenhum remédio cadastrado.")) : ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(10), itemCount: _remediosAgrupados.keys.length, itemBuilder: (context, index) {
              String horario = _remediosAgrupados.keys.elementAt(index);
              List<Remedio> remedios = _remediosAgrupados[horario]!;
              bool isProximo = (horario == _proximoHorarioDestaque);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 5), child: Row(children: [Icon(Icons.access_time, color: isProximo ? Colors.orange[800] : Colors.blueGrey), const SizedBox(width: 10), Text(horario, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isProximo ? Colors.orange[800] : Colors.blueGrey)), if(isProximo) Container(margin: const EdgeInsets.only(left: 10), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(10)), child: Text("PRÓXIMO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange[900])))])),
                  ...remedios.map((r) => Card(
                    elevation: r.isSuspenso ? 0 : 3,
                    color: r.isSuspenso ? Colors.grey[100] : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: r.isSuspenso ? const BorderSide(color: Colors.grey) : BorderSide.none),
                    child: ListTile(
                      onTap: () => _mostrarDialogo(remedioExistente: r),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(backgroundColor: r.isSuspenso ? Colors.grey : (r.tipo == 'colirio' ? Colors.teal.shade100 : Colors.lightBlue.shade100), child: Icon(r.tipo == 'colirio' ? Icons.visibility : Icons.medication, color: r.isSuspenso ? Colors.white : (r.tipo == 'colirio' ? Colors.teal : Colors.lightBlue))),
                      title: Text(r.nome, style: TextStyle(fontWeight: FontWeight.bold, decoration: r.isSuspenso ? TextDecoration.lineThrough : null, color: r.isSuspenso ? Colors.grey : Colors.black87)),
                      subtitle: r.isSuspenso ? const Text("Suspenso", style: TextStyle(color: Colors.orange)) : Text(r.dose),
                      
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (v) { 
                          if(v=='editar') _mostrarDialogo(remedioExistente: r); 
                          if(v=='suspender') _mostrarOpcoesSuspensao(r); 
                          if(v=='retomar') _retomarRemedio(r); 
                          if(v=='excluir') _confirmarExclusao(r); 
                        },
                        itemBuilder: (c) => [
                          const PopupMenuItem(value: 'editar', child: Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 10), Text("Editar")])),
                          if (!r.isFinalizado && !r.isSuspenso) const PopupMenuItem(value: 'suspender', child: Row(children: [Icon(Icons.pause, color: Colors.orange), SizedBox(width: 10), Text("Suspender")])),
                          if (r.isSuspenso) const PopupMenuItem(value: 'retomar', child: Row(children: [Icon(Icons.play_arrow, color: Colors.green), SizedBox(width: 10), Text("Retomar")])),
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'excluir', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 10), Text("Excluir", style: TextStyle(color: Colors.red))])),
                        ]
                      )
                    )
                  )),
              ]);
          })),
      ],),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarDialogo(), 
        icon: const Icon(Icons.add), 
        label: const Text("Novo Remédio")
      ),
    );
  }
}