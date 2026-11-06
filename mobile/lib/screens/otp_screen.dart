import 'package:flutter/material.dart';

import '../state/session.dart';
import '../widgets.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);

    try {
      await AppScope.session(context).verifyCode(widget.phone, _code.text.trim());
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await AppScope.session(context).requestCode(widget.phone);
      if (mounted) showMessage(context, 'Nouveau code envoyé.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Heading('Entrez votre code'),
                  const SizedBox(height: 8),
                  Muted('Nous l\'avons envoyé par SMS au ${widget.phone}.'),
                  const SizedBox(height: 24),
                  const Label('Code à 6 chiffres'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 8),
                    decoration: const InputDecoration(hintText: '000000', counterText: ''),
                    onSubmitted: (_) => _submit(),
                  ),
                  TextButton(onPressed: _resend, child: const Text('Renvoyer le code')),
                  const Spacer(),
                  BusyButton(label: 'Continuer', busy: _busy, onPressed: _submit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
