import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/sanitary_repository.dart';
import '../domain/animal_option.dart';
import '../domain/upcoming_event.dart';
import 'register_event_view_model.dart';
import 'upcoming_events_page.dart' show sanitaryTypeLabel;

/// US-11: ruta del formulario de registro de un evento sanitario; se cierra con true cuando el backend lo registra.
/// Con [animal] (p. ej. desde el detalle de un animal) el formulario ya trae el animal; sin el, deja elegir uno.
Route<bool> registerEventRoute(SanitaryRepository repository, {AnimalOption? animal}) {
  return MaterialPageRoute<bool>(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => RegisterEventViewModel(repository, animal: animal)..loadAnimals(),
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
      firstDate: DateTime(today.year - 10),
      lastDate: DateTime(today.year, today.month, today.day), // un evento ya ocurrido no puede ser futuro
    );
    if (picked != null) viewModel.selectDate(picked);
  }

  Future<void> _submit(RegisterEventViewModel viewModel) async {
    FocusScope.of(context).unfocus();
    final navigator = Navigator.of(context);
    if (await viewModel.submit(_notes.text)) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<RegisterEventViewModel>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.registerEventTitle)),
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
      ConnectionEventError() => l10n.connectionError,
      ServerEventError(:final serverMessage) => serverMessage.isEmpty ? l10n.registerEventError : serverMessage,
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
          const SizedBox(height: 16),
          Text(l10n.registerEventDate, style: Theme.of(context).textTheme.labelMedium),
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
                : Text(l10n.registerEventSubmit),
          ),
        ],
      ),
    );
  }
}
