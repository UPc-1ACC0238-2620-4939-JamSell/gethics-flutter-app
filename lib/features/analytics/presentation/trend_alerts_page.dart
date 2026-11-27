import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/alert_repository.dart';
import '../domain/trend_alert.dart';
import 'trend_alerts_view_model.dart';

/// US-21: ruta de las alertas por tendencia de un propietario. [ownerId] debe venir de una relacion legitima (p. ej. un
/// cliente asignado al veterinario); null o un valor que no es UUID muestra el aviso de propietario no disponible y no
/// consulta nada. Por defecto solo se muestran las alertas sanitarias (ver [TrendAlertsViewModel.allowedTypes]).
Route<void> trendAlertsRoute(
  AlertRepository repository, {
  required String? ownerId,
  Set<TrendType> allowedTypes = const {TrendType.sanitary},
}) {
  return MaterialPageRoute<void>(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => TrendAlertsViewModel(repository, ownerId: ownerId, allowedTypes: allowedTypes)..load(),
      child: const TrendAlertsPage(),
    ),
  );
}

class TrendAlertsPage extends StatelessWidget {
  const TrendAlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<TrendAlertsViewModel>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trendAlertsTitle)),
      body: _body(context, l10n, viewModel),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, TrendAlertsViewModel viewModel) {
    if (!viewModel.hasOwner) return EmptyView(message: l10n.trendAlertsOwnerUnavailable);
    final alerts = viewModel.alerts;
    if (viewModel.loading && alerts == null) return const LoadingView();
    if (alerts == null) {
      return ErrorView(
        message: viewModel.connectionError ? l10n.connectionError : viewModel.message,
        onRetry: viewModel.load,
      );
    }
    if (alerts.isEmpty) {
      return RefreshIndicator(
        onRefresh: viewModel.load,
        child: ListView(children: [SizedBox(height: 320, child: EmptyView(message: l10n.trendAlertsEmpty))]),
      );
    }
    return RefreshIndicator(
      onRefresh: viewModel.load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: alerts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => TrendAlertCard(alert: alerts[index]),
      ),
    );
  }
}

String trendTypeLabel(AppLocalizations l10n, TrendType type) => switch (type) {
      TrendType.sanitary => l10n.trendTypeSanitary,
      TrendType.financial => l10n.trendTypeFinancial,
      TrendType.combined => l10n.trendTypeCombined,
    };

String riskLabel(AppLocalizations l10n, RiskLevel risk) => switch (risk) {
      RiskLevel.low => l10n.riskLow,
      RiskLevel.medium => l10n.riskMedium,
      RiskLevel.high => l10n.riskHigh,
      RiskLevel.critical => l10n.riskCritical,
    };

String alertStatusLabel(AppLocalizations l10n, AlertStatus status) => switch (status) {
      AlertStatus.pending => l10n.alertStatusPending,
      AlertStatus.sent => l10n.alertStatusSent,
      AlertStatus.read => l10n.alertStatusRead,
    };

/// El riesgo se distingue por icono y texto ademas del color, para no depender solo de este.
(IconData, Color, Color) _riskStyle(ColorScheme scheme, RiskLevel? risk) => switch (risk) {
      RiskLevel.low => (Icons.info_outline, GethicsColors.inkVariant, GethicsColors.mint),
      RiskLevel.medium => (Icons.warning_amber_rounded, GethicsColors.alertText, GethicsColors.alertBackground),
      RiskLevel.high => (Icons.error_outline, scheme.error, scheme.error.withValues(alpha: 0.1)),
      RiskLevel.critical => (Icons.dangerous_outlined, scheme.onError, scheme.error),
      null => (Icons.notifications_none_outlined, GethicsColors.inkVariant, GethicsColors.mint),
    };

class TrendAlertCard extends StatelessWidget {
  const TrendAlertCard({super.key, required this.alert});

  final TrendAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final (icon, riskColor, riskBackground) = _riskStyle(scheme, alert.riskLevel);
    final created = alert.createdAt;
    final details = [
      if (alert.status != null) alertStatusLabel(l10n, alert.status!),
      if (created != null) DateFormat.yMMMd(locale).add_Hm().format(created.toLocal()),
    ].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE2E7DF)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: riskBackground, shape: BoxShape.circle),
              child: Icon(icon, color: riskColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (alert.riskLevel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: riskBackground, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            riskLabel(l10n, alert.riskLevel!),
                            style: TextStyle(color: riskColor, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (alert.type != null)
                        Text(
                          trendTypeLabel(l10n, alert.type!),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  if (alert.message.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(alert.message), // texto del backend, tal como llega
                  ],
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(details, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
