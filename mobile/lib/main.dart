import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/courier_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/setup_screen.dart';
import 'state/outbox.dart';
import 'state/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final session = Session(api);
  final outbox = Outbox(api);
  await session.restore();
  await outbox.load();
  runApp(App(session: session, outbox: outbox));
}

class App extends StatelessWidget {
  const App({super.key, required this.session, required this.outbox});

  final Session session;
  final Outbox outbox;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: session,
      outbox: outbox,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => MaterialApp(
          title: 'Superlivraison',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: session.themeMode,
          home: const _Root(),
        ),
      ),
    );
  }
}

/// Choisit l'écran selon l'état du compte, sans pile de navigation à réinitialiser.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final user = session.user;

        if (user == null) return const LoginScreen();
        if (user.isCourier) return const CourierScreen();
        if (user.needsSetup) return const SetupScreen();
        return const HomeShell();
      },
    );
  }
}
