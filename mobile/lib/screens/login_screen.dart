import 'package:flutter/material.dart';

import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+228 ');
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final phone = _phone.text.trim();

    try {
      await AppScope.session(context).requestCode(phone);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtpScreen(phone: phone)));
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
                  const Heading('Tout pour votre restaurant, livré chez vous', size: 30),
                  const SizedBox(height: 28),
                  const Label('Numéro de téléphone'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: '+228 90 00 00 00'),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 28),
                  BusyButton(label: 'Recevoir le code', busy: _busy, onPressed: _submit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
