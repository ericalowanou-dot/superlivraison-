import 'package:flutter/material.dart';

import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'register_screen.dart';

/// Page d'accueil : présentation de l'application et connexion par e-mail.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      showMessage(context, 'Indiquez votre e-mail et votre mot de passe.');
      return;
    }

    setState(() => _busy = true);
    try {
      await AppScope.session(context).login(email, _password.text);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 412),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset('assets/logo.png', width: 88, height: 88, semanticLabel: 'Logo de l\'application'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Superlivraison',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.of(context).link),
                    ),
                    const SizedBox(height: 8),
                    const Heading('Tout ce dont vous avez besoin, livré chez vous', size: 30),
                    const SizedBox(height: 8),
                    const Muted('Colis, courses, repas ou achats en boutique : un livreur s\'en occupe.'),
                    const SizedBox(height: 28),
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
                    const Label('Mot de passe'),
                    const SizedBox(height: 8),
                    PasswordField(controller: _password, onSubmitted: _submit),
                    const SizedBox(height: 28),
                    BusyButton(label: 'Se connecter', busy: _busy, onPressed: _submit),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: const Text('Créer un compte'),
                    ),
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

/// Champ de mot de passe avec un bouton pour l'afficher.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, this.onSubmitted, this.newPassword = false});

  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  final bool newPassword;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
      decoration: InputDecoration(
        suffixIcon: IconButton(
          tooltip: _visible ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
          icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}
