import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../../sanitary/data/sanitary_repository.dart';
import '../../sanitary/domain/animal_option.dart';
import '../../sanitary/presentation/clinical_history_page.dart';
import '../data/livestock_repository.dart';
import '../domain/animal.dart';
import 'animal_detail_view_model.dart';
import 'animal_format.dart';
import 'animal_status_badge.dart';
import 'animal_texts.dart';

/// US-43: ruta de la ficha de un animal. [sanitaryRepository] permite abrir su historial clinico (US-14).
Route<void> animalDetailRoute(LivestockRepository repository, SanitaryRepository sanitaryRepository, String animalId) {
  return MaterialPageRoute<void>(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => AnimalDetailViewModel(repository, animalId)..load(),
      child: AnimalDetailPage(sanitaryRepository: sanitaryRepository),
    ),
  );
}

/// US-43: ficha completa del animal (raza, edad, genero, nacimiento, peso, QR, estado y granja) con acceso a su
/// historial clinico. Se usa dentro de un [AnimalDetailViewModel] provisto por la ruta. Si falla la carga, muestra el
/// error con la opcion de reintentar.
class AnimalDetailPage extends StatelessWidget {
  const AnimalDetailPage({super.key, required this.sanitaryRepository});

  final SanitaryRepository sanitaryRepository;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<AnimalDetailViewModel>();
    final animal = viewModel.animal;
    final error = viewModel.error;
    final Widget body;
    if (error != null) {
      body = ErrorView(message: error.isConnection ? l10n.connectionError : error.message, onRetry: viewModel.load);
    } else if (animal == null) {
      body = const LoadingView();
    } else {
      body = _AnimalDetailContent(
        animal: animal,
        farmName: viewModel.farm?.name,
        today: DateTime.now(),
        onOpenHistory: () => Navigator.of(context).push(
          clinicalHistoryRoute(sanitaryRepository, animal: AnimalOption(id: animal.id, label: animal.name ?? animal.tag)),
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(l10n.animalDetailTitle)), body: body);
  }
}

class _AnimalDetailContent extends StatelessWidget {
  const _AnimalDetailContent({
    required this.animal,
    required this.farmName,
    required this.today,
    required this.onOpenHistory,
  });

  final Animal animal;
  final String? farmName;
  final DateTime today;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = animal.status;
    final weight = animal.weightKg;
    final tiles = [
      _InfoTile(icon: Icons.pets_outlined, label: l10n.animalBreed, value: animal.breed.isEmpty ? noData : animal.breed),
      _InfoTile(icon: Icons.cake_outlined, label: l10n.animalAge, value: ageText(l10n, animal.birthDate, today)),
      _InfoTile(
        icon: animal.sex == 'MALE' ? Icons.male : Icons.female,
        label: l10n.animalGender,
        value: sexText(l10n, animal.sex),
      ),
      _InfoTile(icon: Icons.calendar_month_outlined, label: l10n.animalBirthDate, value: formatBirthDate(animal.birthDate)),
      _InfoTile(
        icon: Icons.monitor_weight_outlined,
        label: l10n.animalWeight,
        value: weight == null ? noData : l10n.animalWeightValue(formatWeight(weight)),
      ),
      _InfoTile(icon: Icons.qr_code_2, label: l10n.animalQr, value: animal.qrCode ?? noData),
      _InfoTile(
        icon: Icons.info_outline,
        label: l10n.animalStatus,
        value: status == null ? noData : statusLabel(l10n, status),
      ),
      _InfoTile(
        icon: Icons.agriculture_outlined,
        label: l10n.animalFarm,
        value: animal.farmId == null ? l10n.animalNoFarm : farmName ?? noData,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                animal.name ?? animal.tag,
                style: Theme.of(context).textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            AnimalStatusBadge(status: status),
          ],
        ),
        const SizedBox(height: 4),
        Text(animal.tag, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        for (var i = 0; i < tiles.length; i += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: onOpenHistory,
          icon: const Icon(Icons.history),
          label: Text(l10n.animalViewHistory),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}
