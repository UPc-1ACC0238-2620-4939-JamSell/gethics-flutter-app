import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/sanitary_repository.dart';
import '../data/sanitary_sync_service.dart';
import '../domain/animal_option.dart';
import '../domain/upcoming_event.dart';
import 'register_event_view_model.dart';
import 'upcoming_events_page.dart' show sanitaryTypeLabel;

/// US-11: ruta del formulario de registro de un evento sanitario. Se cierra con [SanitarySaveResult.sent] cuando el
/// backend lo registra o [SanitarySaveResult.queued] si quedo guardado sin conexion (US-35); null si se sale sin guardar.
/// Con [animal] (p. ej. desde el detalle de un animal) el formulario ya trae el animal; sin el, deja elegir uno.
Route<SanitarySaveResult> registerEventRoute(SanitaryRepository repository, {AnimalOption? animal}) =>
    _formRoute(repository, animal: animal, scheduleVaccination: false);

/// US-13: ruta del mismo formulario para programar una vacuna (fecha de hoy en adelante). Mismo resultado y parametro
/// [animal] que [registerEventRoute].
Route<SanitarySaveResult> scheduleVaccinationRoute(SanitaryRepository repository, {AnimalOption? animal}) =>
    _formRoute(repository, animal: animal, scheduleVaccination: true);

/// Aviso a mostrar al volver del formulario: [sentMessage] si el backend lo confirmo, el de guardado sin conexion si
/// quedo en la cola, null si no se guardo nada.
String? saveResultMessage(AppLocalizations l10n, SanitarySaveResult? result, {required String sentMessage}) =>
    switch (result) {
      SanitarySaveResult.sent => sentMessage,
      SanitarySaveResult.queued => l10n.sanitarySavedOffline,
      null => null,
    };

Route<SanitarySaveResult> _formRoute(SanitaryRepository repository, {AnimalOption? animal, required bool scheduleVaccination}) {
  return MaterialPageRoute<SanitarySaveResult>(
    builder: (_) => ChangeNotifierProvider(
      create: (_) =>
          RegisterEventViewModel(repository, animal: animal, scheduleVaccination: scheduleVaccination)..loadAnimals(),
      child: const RegisterEventPage(),
    ),
  );
}

class RegisterEventPage extends StatefulWidget {
  const RegisterEventPage({super.key});

  @override
  State<RegisterEventPage> createState() => _RegisterEventPageState();
}

class _RegisterEventPageState extends State<RegisterEventPage> {
  static const _notesMax = 1000; // mismo limite que valida el backend

  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(RegisterEventViewModel viewModel) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: viewModel.date,
      // Un evento ya ocurrido no puede ser futuro; una vacuna programada no puede ser pasada.
      firstDate: viewModel.scheduling ? DateTime(today.year, today.month, today.day) : DateTime(today.year - 10),
      lastDate: viewModel.scheduling ? DateTime(today.year + 5, today.month, today.day) : DateTime(today.year, today.month, today.day),
    );
    if (picked != null) viewModel.selectDate(picked);
  }

  Future<void> _submit(RegisterEventViewModel viewModel) async {
    FocusScope.of(context).unfocus();
    final navigator = Navigator.of(context);
    final result = await viewModel.submit(_notes.text);
    if (result != null) navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<RegisterEventViewModel>();
    return Scaffold(
      appBar: AppBar(title: Text(viewModel.scheduling ? l10n.scheduleVaccinationTitle : l10n.registerEventTitle)),
      body: _body(context, l10n, viewModel),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, RegisterEventViewModel viewModel) {
    final animals = viewModel.animals;
    if (!viewModel.lockedAnimal) {
      if (animals == null) {
        if (viewModel.loadingAnimals) return const LoadingView();
        return ErrorView(
          message: viewModel.animalsConnectionError ? l10n.connectionError : viewModel.animalsMessage,
          onRetry: viewModel.loadAnimals,
        );
      }
      if (animals.isEmpty) return EmptyView(message: l10n.registerEventNoAnimals);
    }

    final locale = Localizations.localeOf(context).toLanguageTag();
    final busy = viewModel.submitting;
    final missing = viewModel.error is MissingFieldsEventError;
    final error = switch (viewModel.error) {
      null || MissingFieldsEventError() => null,
      FutureDateEventError() => l10n.registerEventFutureDate,
      PastDateEventError() => l10n.scheduleVaccinationPastDate,
      ConnectionEventError() => l10n.connectionError,
      ServerEventError(:final serverMessage) => serverMessage.isEmpty
          ? (viewModel.scheduling ? l10n.scheduleVaccinationError : l10n.registerEventError)
          : serverMessage,
    };

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (viewModel.lockedAnimal)
            InputDecorator(
              decoration: InputDecoration(labelText: l10n.registerEventAnimal),
              child: Text(viewModel.animal!.label),
            )
          else
            DropdownButtonFormField<AnimalOption>(
              key: const Key('register-animal'),
              initialValue: viewModel.animal,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.registerEventAnimal,
                errorText: missing && viewModel.animal == null ? l10n.registerEventRequired : null,
              ),
              items: [
                for (final animal in animals!)
                  DropdownMenuItem(value: animal, child: Text(animal.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: busy ? null : viewModel.selectAnimal,
            ),
          const SizedBox(height: 16),
          if (!viewModel.scheduling)
            DropdownButtonFormField<SanitaryEventType>(
            key: const Key('register-type'),
            initialValue: viewModel.type,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.registerEventType,
              errorText: missing && viewModel.type == null ? l10n.registerEventRequired : null,
            ),
            items: [
              for (final type in SanitaryEventType.values)
                DropdownMenuItem(value: type, child: Text(sanitaryTypeLabel(l10n, type))),
            ],
            onChanged: busy ? null : viewModel.selectType,
          ),
          if (!viewModel.scheduling) const SizedBox(height: 16),
          Text(viewModel.scheduling ? l10n.scheduleVaccinationDate : l10n.registerEventDate, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            key: const Key('register-date'),
            onPressed: busy ? null : () => _pickDate(viewModel),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DateFormat.yMMMMd(locale).format(viewModel.date)),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('register-notes'),
            controller: _notes,
            enabled: !busy,
            maxLength: _notesMax,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.registerEventNotes, alignLabelWithHint: true),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('register-submit'),
            onPressed: busy ? null : () => _submit(viewModel),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(viewModel.scheduling ? l10n.scheduleVaccinationSubmit : l10n.registerEventSubmit),
          ),
        ],
      ),
    );
  }
}
