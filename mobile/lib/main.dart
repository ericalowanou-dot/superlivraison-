import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/chat_screen.dart';
import 'screens/courier_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/order_screen.dart';
import 'screens/setup_screen.dart';
import 'state/outbox.dart';
import 'state/push.dart';
import 'state/session.dart';
import 'theme.dart';

final _navigator = GlobalKey<NavigatorState>();
final _messenger = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final session = Session(api);
  final outbox = Outbox(api);
  final push = Push(api);
  session.deviceToken = () => push.token;
  await session.restore();
  await outbox.load();
  await push.init();
  _wirePush(session, push);
  runApp(App(session: session, outbox: outbox));
}

/// Branche les notifications sur la session : enregistrement à la connexion, ouverture au toucher.
void _wirePush(Session session, Push push) {
  var registered = false;
  void sync() {
    if (session.user != null && !registered) {
      registered = true;
      push.register();
    } else if (session.user == null) {
      registered = false;
    }
  }

  session.addListener(sync);
  sync();

  push.onOpen = (target) => _openTarget(session, target);
  push.onForeground = (target) {
    // Déjà dans cette discussion : le message s'affiche à l'écran, inutile de le signaler.
    if (target.isMessage && target.orderId == ChatScreen.visibleOrderId) return;

    _messenger.currentState?.showSnackBar(SnackBar(
      content: Text([target.title, target.body].whereType<String>().join(' : ')),
      action: target.orderId == null
          ? null
          : SnackBarAction(label: 'Ouvrir', onPressed: () => _openTarget(session, target)),
    ));
  };

  WidgetsBinding.instance.addPostFrameCallback((_) => push.openPending());
}

void _openTarget(Session session, PushTarget target) {
  final user = session.user;
  final navigator = _navigator.currentState;
  final orderId = target.orderId;
  if (user == null || navigator == null || orderId == null) return;

  if (target.isMessage) {
    if (ChatScreen.visibleOrderId == orderId) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => ChatScreen(orderId: orderId, reference: target.reference ?? 'Course'),
    ));
  } else if (!user.isCourier) {
    // Le livreur voit déjà ses livraisons sur son écran d'accueil.
    navigator.push(MaterialPageRoute(builder: (_) => OrderScreen(orderId: orderId)));
  }
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
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
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
