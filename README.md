# DailyDose

DailyDose é um aplicativo mobile em Flutter para organização, lembrete e controle de medicamentos. O objetivo principal é facilitar a rotina de medicação, especialmente em casos em que o usuário precisa tomar vários remédios em horários específicos ao longo do dia.

## Visão geral

O projeto foi pensado para reduzir esquecimentos e melhorar a segurança do uso de medicamentos. A aplicação permite cadastrar uma lista personalizada de remédios, definir horários de administração, controlar frequência e receber alertas quando a dose deve ser tomada.

A estrutura foi organizada para funcionar como um gerenciador simples e eficiente de alarmes de medicação, com persistência local, notificações e suporte a diferentes tipos de tratamento.

## Funcionalidades principais

- Cadastro de medicamentos e colírios
- Edição e exclusão de itens cadastrados
- Organização por horário de tomada
- Definição de dose e tipo de medicamento
- Frequência diária, semanal e por intervalo de dias
- Controle de suspensão temporária
- Encerramento de tratamento por data final
- Notificações e tela de alarme ao disparar o lembrete
- Armazenamento local em SQLite
- Histórico de uso e acompanhamento da rotina
- Leitura em voz alta para maior acessibilidade

## Como o sistema funciona

O usuário registra cada medicamento com nome, dose, tipo e horário. A aplicação agrupa esses itens por momento do dia e verifica se o remédio deve ser lembrado na data atual.

Quando o horário chega, o app dispara o alarme e exibe uma tela destacada com as informações do medicamento. Em alguns cenários, também é possível anunciar o lembrete em voz alta para facilitar a rotina e ampliar a experiência de uso.

## Arquitetura do projeto

O DailyDose segue uma organização simples em camadas, com separação entre modelos, telas e serviços.

### Camada de modelos

- `lib/models/remedio.dart`: define a estrutura do medicamento e os campos de frequência.

### Camada de interface

- `lib/screens/home_screen.dart`: tela principal, com listagem e organização dos remédios.
- `lib/screens/alarm_screen.dart`: tela de alarme que aparece quando o lembrete dispara.
- `lib/screens/permission_screen.dart`: gerenciamento das permissões necessárias.

### Camada de serviços

- `lib/services/remedio_service.dart`: banco de dados, filtros e lógica de frequência.
- `lib/services/notification_service.dart`: criação e disparo de notificações.
- `lib/services/background_service.dart`: processamento em segundo plano.
- `lib/services/tts_service.dart`: leitura por voz dos medicamentos.

## Banco de dados e persistência

A aplicação usa SQLite para armazenar os dados localmente no dispositivo. O banco mantém as informações dos remédios e também o histórico de uso, permitindo que o app funcione mesmo sem conexão com internet.

A persistência foi implementada para garantir que o cadastro do usuário seja mantido entre execuções e que as regras de programação dos remédios continuem consistentes.

## Tecnologias e dependências

- Flutter
- Dart
- SQLite com sqflite
- flutter_local_notifications
- android_alarm_manager_plus
- flutter_tts
- permission_handler
- intl
- shared_preferences

## Estrutura do projeto

```text
lib/
├── main.dart
├── models/
│   └── remedio.dart
├── screens/
│   ├── alarm_screen.dart
│   ├── home_screen.dart
│   └── permission_screen.dart
├── services/
│   ├── background_service.dart
│   ├── notification_service.dart
│   ├── remedio_service.dart
│   └── tts_service.dart
└──

test/
└── widget_test.dart
```

## Como executar

1. Instale o Flutter e o Dart.
2. Acesse a pasta do projeto:

```bash
cd alarmeremedio
```

3. Instale as dependências do projeto antes de rodar o app:

```bash
flutter pub get
```

4. Execute o app:

```bash
flutter run
```

5. Se quiser validar os testes:

```bash
flutter test
```

## Observações finais

O DailyDose foi pensado para uso prático no dia a dia, especialmente em rotinas de medicação mais complexas, com múltiplos horários e diferentes tipos de medicamento. A proposta central é manter o lembrete confiável, a interface simples de usar e o controle organizado do tratamento.
