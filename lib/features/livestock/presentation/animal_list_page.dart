import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/animal.dart';
import 'animal_list_view_model.dart';
import 'animal_status_badge.dart';
import 'animal_texts.dart';

/// US-42: buscador por arete, nombre o raza, filtro por estado, boton para limpiar filtros y listado. Se usa dentro
/// de un [AnimalListViewModel] provisto por el padre; [onOpenAnimal] abre la ficha del animal (US-43).
class AnimalListPage extends StatefulWidget {
  const AnimalListPage({super.key, required this.onOpenAnimal});

  final void Function(String animalId) onOpenAnimal;

  @override
  State<AnimalListPage> createState() => _AnimalListPageState();
}

class _AnimalListPageState extends State<AnimalListPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    // El ViewModel vive mas que esta pantalla (al cambiar de pestana se reconstruye): el campo parte de su busqueda.
    _searchController = TextEditingController(text: context.read<AnimalListViewModel>().query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<AnimalListViewModel>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: viewModel.onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.animalsSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: viewModel.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.animalsSearchClear,
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        viewModel.onQueryChanged('');
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final status in AnimalStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(statusFilterLabel(l10n, status)),
                    selected: viewModel.status == status,
                    onSelected: (_) => viewModel.onStatusChanged(status),
                  ),
                ),
            ],
          ),
        ),
        if (viewModel.hasActiveFilters)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: () {
                  _searchController.clear();
                  viewModel.clearFilters();
                },
                child: Text(l10n.animalsClearFilters),
              ),
            ),
          ),
        Expanded(child: _Content(viewModel: viewModel, onOpenAnimal: widget.onOpenAnimal)),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.viewModel, required this.onOpenAnimal});

  final AnimalListViewModel viewModel;
  final void Function(String animalId) onOpenAnimal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = viewModel.error;
    if (error != null) {
      return ErrorView(message: error.isConnection ? l10n.connectionError : error.message, onRetry: viewModel.load);
    }
    if (viewModel.loading && viewModel.animals.isEmpty) return const LoadingView();
    if (viewModel.animals.isEmpty) {
      return EmptyView(message: viewModel.hasActiveFilters ? l10n.animalsNoResults : l10n.animalsNone);
    }
    return Column(
      children: [
        if (viewModel.loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: viewModel.animals.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final animal = viewModel.animals[index];
              return _AnimalCard(animal: animal, onTap: () => onOpenAnimal(animal.id));
            },
          ),
        ),
      ],
    );
  }
}

class _AnimalCard extends StatelessWidget {
  const _AnimalCard({required this.animal, required this.onTap});

  final Animal animal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.pets)),
        title: Row(
          children: [
            Flexible(child: Text(animal.tag, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            AnimalStatusBadge(status: animal.status),
          ],
        ),
        subtitle: Text(animal.breed),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
