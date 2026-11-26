import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import 'sign_in_view_model.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(SignInViewModel viewModel) async {
    if (await viewModel.signIn(_email.text, _password.text)) {
      widget.onSignedIn();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewModel = context.watch<SignInViewModel>();
    final error = switch (viewModel.error) {
      null => null,
      EmptyFieldsError() => l10n.signInEmptyFields,
      ConnectionSignInError() => l10n.connectionError,
      ServerSignInError(:final serverMessage) => serverMessage.isEmpty ? l10n.genericError : serverMessage,
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.appTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(l10n.signInSubtitle, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                Text(l10n.signInTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  enabled: !viewModel.loading,
                  decoration: InputDecoration(labelText: l10n.emailLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  enabled: !viewModel.loading,
                  decoration: InputDecoration(labelText: l10n.passwordLabel),
                  onSubmitted: (_) => _submit(viewModel),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: viewModel.loading ? null : () => _submit(viewModel),
                  child: viewModel.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.signInButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
