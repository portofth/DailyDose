# DailyDose

## Descrição do projeto

DailyDose é um aplicativo Flutter para organização, lembrete e controle de medicamentos. Ele foi pensado para ajudar o usuário a acompanhar remédios e colírios de forma mais segura, com foco em horários, frequência e rotina diária.

## Objetivo

O sistema tem como principal objetivo reduzir esquecimentos e facilitar o acompanhamento da medicação, especialmente em tratamentos com vários horários e combinações diferentes de remédios.

## Como o sistema funciona

O usuário cadastra os medicamentos com nome, dose, horário e tipo. A aplicação organiza esses itens por horário e verifica se um remédio deve ser lembrado na data atual. Quando chega o momento do lembrete, o app dispara um alarme e exibe uma tela de destaque com as informações da dose.

## Principais funcionalidades

- Cadastro, edição e exclusão de remédios
- Tratamento para medicamentos gerais e colírios
- Organização por horário e frequência
- Agendamento por dia da semana ou intervalo de dias
- Suspensão temporária do tratamento
- Controle de fim de uso ou data de término
- Persistência local em SQLite
- Histórico de uso e lembretes automáticos
- Suporte a alertas visuais e leitura em voz alta

## Arquitetura técnica

A aplicação foi organizada em camadas para manter a manutenção simples:

- `lib/models`: modelos de dados
- `lib/screens`: telas da interface
- `lib/services`: regras de negócio, banco, notificações e TTS
- `test`: testes automatizados

## Tecnologias principais

- Flutter
- Dart
- SQLite
- flutter_local_notifications
- android_alarm_manager_plus
- flutter_tts
- permission_handler
- intl

## Como executar

```bash
flutter pub get
flutter run
```

## Conclusão

O DailyDose foi desenvolvido como uma solução prática para organização de medicamentos, com foco em lembretes confiáveis, controle de rotina e experiência de uso simples para quem precisa tomar remédios em horários específicos.
