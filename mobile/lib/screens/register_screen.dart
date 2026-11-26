import 'package:flutter/material.dart';

import '../state/session.dart';
import '../widgets.dart';
import 'login_screen.dart';

/// Création d'un compte avec un e-mail et un mot de passe.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController(text: '+228 ');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _problem() {
    if (_name.text.trim().isEmpty) return 'Indiquez votre nom.';
    if (!_email.text.trim().contains('@')) return 'Indiquez une adresse e-mail valide.';
    if (_password.text.length < 8) return 'Le mot de passe doit contenir au moins 8 caractères.';
    if (_password.text != _confirm.text) return 'Les deux mots de passe ne sont pas identiques.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _problem();
    if (problem != null) {
      showMessage(context, problem);
      return;
    }

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    // Le préfixe seul compte comme « pas de numéro ».
    final phone = _phone.text.replaceAll(RegExp(r'[^0-9]'), '').length > 3 ? _phone.text.trim() : null;

    try {
      await AppScope.session(context).register(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: phone,
        password: _password.text,
      );
      // Connecté : l'accueil affiche maintenant le choix du pays et de la ville.
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 412),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Heading('Créer un compte'),
                    const SizedBox(height: 8),
                    const Muted('Quelques informations pour commencer.'),
                    const SizedBox(height: 24),
                    const Label('Nom complet'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                    ),
                    const SizedBox(height: 16),
                    const Label('Adresse e-mail'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(hintText: 'vous@exemple.com'),
                    ),
                    const SizedBox(height: 16),
                    const Label('Téléphone (facultatif)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(helperText: 'Pour que le livreur puisse vous appeler.'),
                    ),
                    const SizedBox(height: 16),
                    const Label('Mot de passe'),
                    const SizedBox(height: 8),
                    PasswordField(controller: _password, newPassword: true),
                    const SizedBox(height: 4),
                    const Muted('Au moins 8 caractères.'),
                    const SizedBox(height: 16),
                    const Label('Confirmer le mot de passe'),
                    const SizedBox(height: 8),
                    PasswordField(controller: _confirm, newPassword: true, onSubmitted: _submit),
                    const SizedBox(height: 28),
                    BusyButton(label: 'Créer mon compte', busy: _busy, onPressed: _submit),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
