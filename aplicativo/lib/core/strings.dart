import 'package:intl/intl.dart';

import 'models.dart';
import '../data/native_health.dart';

abstract final class S {
  static const app = 'ATLETA';
  static const today = 'Hoje', progress = 'Progresso', workouts = 'Treinos';
  static const load = 'Carga de treino', readiness = 'Prontidão';
  static const latestWorkout = 'Último treino',
      connectM5 = 'Conectar M5',
      viewWorkout = 'Ver treino',
      watchStartHint = 'O treino começa ao conectar',
      dashboardRegister = 'Registrar',
      historyOptions = 'Opções do histórico',
      lostConnection = 'Conexão com o M5 perdida',
      m5Connecting = 'Conectando ao M5…',
      m5Connected = 'M5 conectado',
      stepsByDay = 'Passos por dia',
      distance = 'Distância',
      noStepHistory = 'Os passos aparecem aqui após salvar um treino do M5.';
  static const profile = 'Profile & Settings',
      integration = 'Data sources',
      manual = 'Manual records';
  static const back = 'Voltar',
      save = 'Salvar',
      cancel = 'Cancelar',
      retry = 'Tentar novamente',
      remove = 'Remover';
  static const addWorkout = 'Registrar treino',
      editWorkout = 'Editar treino',
      deleteWorkout = 'Excluir treino';
  static const activity = 'Atividade',
      startTime = 'Início',
      duration = 'Duração',
      durationInput = 'Duração (minutos)',
      effort = 'Esforço percebido',
      effortInput = 'Esforço percebido (0–10)',
      notes = 'Notas',
      optionalNotes = 'Notas (opcional)',
      source = 'Origem';
  static const startSession = 'Usar cronômetro',
      pause = 'Pausar',
      resume = 'Retomar',
      finish = 'Finalizar',
      finishSession = 'Finalizar treino',
      running = 'Em andamento',
      paused = 'Pausado';
  static const noWorkouts = 'Nenhum treino registrado.',
      noneFiltered = 'Nenhum treino para estes filtros.',
      allTypes = 'Atividades',
      allDates = 'Todas as datas';
  static const workoutHistory = 'Histórico',
      clearHistory = 'Limpar histórico',
      clearHistoryTitle = 'Limpar histórico de treinos?',
      clearHistoryMessage =
          'Todos os treinos salvos deste perfil serão excluídos, em todas as datas.',
      historyCleared = 'Histórico de treinos limpo';
  static const otherActivity = 'Other';
  static const exerciseList = [
    'Aerobics',
    'Cycling',
    'Running',
    'Strength',
    'Swimming',
    'Walking',
    otherActivity,
  ];
  static const addReadiness = 'Registrar prontidão',
      editReadiness = 'Editar prontidão';
  static const readinessHistory = 'Histórico de prontidão',
      readinessInput = 'Quão preparado você se sente hoje?',
      readinessMethod =
          'Rate your perceived readiness from 0 to 100. The score is your self-assessment.',
      readinessBands = '0–49 Low · 50–79 Moderate · 80–100 High',
      readinessDemo =
          'You’ve started light, and your readiness can\nhold up for another session. To keep it\nproductive, stay within your limits if you decide\nto give it a go.',
      readinessReal = 'Based on your daily self-assessment.',
      readinessEmpty = 'Log a self-assessment to track how ready you feel.',
      readinessSource = 'Self-assessment',
      readinessNoHistory = 'No readiness scores in this period.';
  static const addRest = 'Confirm rest day',
      undoRest = 'Undo rest day',
      confirmRest = 'Confirm rest',
      restHelp =
          'Confirm that you did no training on this date. It will count as a recorded day with zero load.',
      emptyLoad = 'No training load ratio in this period.',
      loadDemo =
          'Training load is near your 28-day average. The ratio compares recent training with your longer-term workload.',
      loadInfo =
          'The last 7 days’ average load divided by the last 28 days’ average load.',
      loadRules = 'A workout’s load is its duration in minutes × perceived effort (0–10). Daily load adds all workouts. The ratio needs 28 consecutive dates with logged workouts or confirmed rest, and a nonzero 28-day average. A workout without an effort score leaves that date incomplete.',
      loadBandsInfo = 'In the demo chart the shaded bands illustrate ratio ranges. For your data, shading marks equal 7- and 28-day loads. The ratio describes training volume and effort.',
      loadDemoBandTop = 'High Risk',
      loadDemoBandMiddle = 'Medium Risk',
      loadDemoBandNear = 'Optimal',
      loadDemoBandBottom = 'Detraining',
      loadDemoBandExplanation = 'The band names reproduce the visual demo. They are illustrative and cannot predict injuries.',
      adjustEffort = 'Add local effort',
      importedEffort = 'Imported workout · effort saved locally',
      missingEffort = 'Add perceived effort to include this workout in training load.',
      importedLocked = 'You can add or change the local effort rating. The original record stays with the connected source.';
  static const avg = 'Average',
      min = 'Minimum',
      max = 'Maximum',
      latest = 'Latest',
      period = 'Period',
      previous = 'Período anterior',
      next = 'Próximo período',
      chartEmpty = 'No data for this period',
      chartDetail = 'Chart point',
      chartLoading = 'Loading…';
  static const demo = 'Demo · sample data',
      demoProfile = 'Demonstration data',
      demoOnly = 'This session uses a separate, temporary demo database.',
      demoOutside = 'ATLETA demo preview',
      metrics = 'About the metrics';
  static const name = 'Name',
      choosePhoto = 'Choose photo',
      removePhoto = 'Remove photo',
      saveProfile = 'Save profile',
      profilePhoto = 'Profile photo',
      photoError = 'Could not open that photo.',
      photoMax = 'Choose an image under 2 MB.',
      dataLocal =
          'Records entered here are stored on this device or in this browser.',
      chooseProfile = 'Choose your profile',
      profileHelp =
          'Create or choose a profile to keep your own training history on this device.',
      createProfile = 'Create profile',
      switchProfile = 'Switch profile',
      localHistory = 'Existing local history',
      nameExistingProfile = 'Name this profile',
      continueProfile = 'Continue',
      openProfileFailed = 'Could not open this profile. Try again.',
      profileNameInUse = 'A profile already uses this name. Choose another name.',
      heightCm = 'Height (cm)',
      weightKg = 'Weight (kg)',
      birthYear = 'Birth year',
      stepLengthCm = 'Step length (cm)',
      optionalProfileFields = 'Height, weight, birth year, step length and photo are optional.',
      heightInvalid = 'Enter a height from 30 to 300 cm.',
      weightInvalid = 'Enter a weight from 1 to 700 kg.',
      birthYearInvalid = 'Enter a valid birth year.',
      stepLengthInvalid = 'Enter a step length from 10 to 250 cm.',
      healthLinked = 'This device’s health data is linked to another local profile. Stop importing in that profile before connecting here.',
      healthName = 'HealthKit / Health Connect',
      connect = 'Connect',
      manage = 'Review access',
      disconnect = 'Stop importing',
      sync = 'Sync now',
      installConnect = 'Get Health Connect',
      healthNotice = 'Reads workouts from the last 30 days. Once enabled, ATLETA refreshes on return. Imported records stay local if you stop importing.',
      noSync = 'No successful sync yet.',
      restricted = 'No read permissions granted. Review access in Health Connect.',
      healthEmpty = 'No readable samples returned. Add data or review sharing in the health app.',
      healthUnsupported = 'Health integrations are available on compatible iOS and Android devices.',
      healthUnavailable = 'The health data service is unavailable on this device.',
      healthInstall = 'Install or update Health Connect to continue.',
      healthReady = 'Ready to request read access.',
      healthFailed = 'The health service could not complete the sync.',
      healthSynced = 'Health data refreshed.',
      healthReading = 'Reading health data…',
      privacy = 'Health data and permissions',
      privacyBody = 'ATLETA reads workouts when you enable a health integration. Imports and manual records are stored locally. ATLETA does not write records to the health service. Review or revoke permissions in Apple Health or Health Connect.';
  static const future = 'Choose a time that has already passed.',
      required = 'Enter a value.',
      durationInvalid = 'Enter a duration from 1 second to 24 hours.',
      readinessInvalid = 'Enter a number from 0 to 100.',
      duplicate = 'This record already exists or conflicts with a workout.',
      failed = 'Could not save. Try again.',
      openFailed = 'Could not open local data.',
      saved = 'Saved',
      deleted = 'Workout deleted',
      deleteQuestion =
          'Delete this local workout? Its load will be recalculated.';
  static const clearDate = 'Limpar data',
      editProfile = 'Edit profile',
      importedSources = 'Imported sources',
      metricsToday = 'Training Metrics';
  static const noValue = '—',
      markRest = 'Dias de descanso',
      addRestHelp = 'Choose a date to confirm or remove a rest day.';
  static const date = 'Date',
      time = 'Time',
      type = 'Type',
      recorded = 'Recorded',
      updated = 'Updated',
      totalDuration = 'Total duration',
      confirmed = 'Confirmed rest day';
  static const m5Watch = 'Relógio M5',
      m5Help =
          'Segure o botão B do M5StickC Plus2 para ligar o Bluetooth e mantenha o relógio por perto.',
      m5Choose = 'Buscar relógio M5',
      m5Select = 'Escolha seu M5',
      m5Searching = 'Buscando relógio M5…',
      m5Pairing = 'Aguardando pareamento',
      m5PairingHelp =
          'Abra o aviso do Android para Atleta-M5 e toque em Parear.',
      m5PairingFailed = 'Pareamento pendente. Tente novamente e aceite o aviso do Android.',
      m5None = 'Nenhum M5 encontrado. Ligue o Bluetooth no relógio e tente novamente.',
      m5Failed = 'Falha na conexão. Confira o Bluetooth, as permissões e o relógio.',
      m5LinkConflict = 'O M5 está vinculado a outro perfil. Remova o vínculo nesse perfil primeiro.',
      m5Unlinked = 'Conecte para ver passos, tempo e bateria.',
      m5Disconnected = 'Desconectado',
      m5Reconnect = 'Reconectar M5',
      m5Disconnect = 'Desconectar M5',
      m5Forget = 'Remover vínculo com o M5',
      m5Waiting = 'Aguardando dados do M5',
      m5Live = 'Dados do M5',
      stepsUnit = 'passos',
      m5Steps = 'Passos',
      m5Distance = 'Distância estimada',
      m5Battery = 'Bateria do relógio',
      m5ActiveTime = 'Tempo ativo',
      m5Start = 'Iniciar no M5',
      m5Save = 'Salvar treino',
      m5Ready = 'Pronto para iniciar',
      m5Stopped = 'Treino finalizado',
      m5NextWorkout = 'Salve ou descarte este treino para começar outro.',
      m5ResumeOnWatch = 'Pressione o botão A do M5 para retomar no relógio.',
      m5ControlFailed = 'O M5 não confirmou o comando. Confira o Bluetooth e tente novamente.',
      m5AutoStartFailed = 'M5 conectado. Toque em Iniciar no M5 para tentar novamente.',
      m5Legacy = 'Pressione A no relógio para pausar ou segure A para iniciar uma sessão. Pause para importar. O firmware 2.1.8 permite usar os controles do app.',
      m5Sensors = 'Informe o comprimento do passo no perfil para estimar a distância.',
      m5DiscardDraft = 'Descartar treino do M5',
      m5DiscardQuestion = 'Descartar este treino ainda não salvo? Para zerar uma sessão em aberto no M5, segure o botão A.',
      m5Busy = 'Finalize ou descarte o treino em andamento primeiro.',
      m5InvalidTime = 'Registre pelo menos um segundo de treino para salvar.';

  static String day(DateTime date) =>
      DateFormat('MMM d, y', 'en_US').format(date.toLocal());
  static const _months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  static String month(DateTime date) => _months[date.month - 1];
  static String shortDay(DateTime date) => '${date.day} ${month(date)}';
  static String shortPeriod(DateTime start, DateTime end) {
    if (start.year != end.year) {
      return '${shortDay(start)} ${start.year} – ${shortDay(end)} ${end.year}';
    }
    if (start.month == end.month) return '${start.day}–${shortDay(end)}';
    return '${shortDay(start)} – ${shortDay(end)}';
  }

  static String weekday(DateTime date) =>
      const ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][date.weekday - 1];
  static final _integer = NumberFormat.decimalPattern('pt_BR');
  static final _km = NumberFormat('0.00', 'pt_BR');
  static String number(int value) => _integer.format(value);
  static String kilometers(double value) => '${_km.format(value)} km';
  static String stopwatch(int seconds) =>
      durationLabel(seconds).padLeft(8, '0');
  static String compactDuration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes == 0) return '${seconds}s';
    if (minutes < 60) return '$minutes min';
    if (minutes % 60 == 0) return '${minutes ~/ 60}h';
    return '${minutes ~/ 60}h ${minutes % 60}min';
  }

  static String activityName(String type) => switch (type.toLowerCase()) {
    'aerobics' || 'aeróbica' => 'Aeróbica',
    'cycling' || 'ciclismo' => 'Ciclismo',
    'running' || 'corrida' => 'Corrida',
    'strength' || 'musculação' => 'Musculação',
    'swimming' || 'natação' => 'Natação',
    'walking' || 'caminhada' => 'Caminhada',
    'other' || 'outra atividade' => 'Outra atividade',
    _ => type,
  };
  static String clock(DateTime date) =>
      DateFormat('HH:mm', 'en_US').format(date.toLocal());
  static String timestamp(DateTime date) => '${day(date)} · ${clock(date)}';
  static String profileDetails(AthleteProfile profile) => [
    if (profile.heightCm case final height?) '${_decimal(height)} cm',
    if (profile.weightKg case final weight?) '${_decimal(weight)} kg',
    if (profile.birthYear case final year?) year.toString(),
  ].join(' · ');
  static String _decimal(double value) =>
      NumberFormat('0.##', 'en_US').format(value);
  static String durationLabel(int seconds) {
    String part(int value) => value.toString().padLeft(2, '0');
    return '${seconds ~/ 3600}:${part(seconds ~/ 60 % 60)}:${part(seconds % 60)}';
  }

  static String periodLabel(int days) => '${days}D';
  static String overview(int days) =>
      days == 28 ? '4-WEEK OVERVIEW' : '$days-DAY OVERVIEW';
  static String coverage(int samples, int days) =>
      '$samples of $days days recorded';
  static String loadCoverage(int known) =>
      '$known of the last 28 days confirmed';
  static String readinessLabel(int value) => switch (value) {
    < 50 => 'Low Readiness',
    < 80 => 'Moderate Readiness',
    _ => 'High Readiness',
  };
  static String origin(Origin value) => switch (value) {
    Origin.manual => 'Manual',
    Origin.timer => 'Workout timer',
    Origin.healthKit => 'Apple HealthKit',
    Origin.healthConnect => 'Health Connect',
    Origin.demo => 'Demonstration',
    Origin.m5 => m5Watch,
  };
  static String healthStatus(HealthStatus value) => switch (value) {
    HealthStatus.unsupported => healthUnsupported,
    HealthStatus.checking => chartLoading,
    HealthStatus.unavailable => healthUnavailable,
    HealthStatus.installRequired => healthInstall,
    HealthStatus.ready => healthReady,
    HealthStatus.reading => healthReading,
    HealthStatus.restricted => restricted,
    HealthStatus.empty => healthEmpty,
    HealthStatus.synced => healthSynced,
    HealthStatus.failed => healthFailed,
    HealthStatus.linkedElsewhere => healthLinked,
  };
}
