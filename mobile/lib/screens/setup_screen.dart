import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';

/// Choix de la langue, du pays et de la ville : au premier lancement et depuis les réglages.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  /// Au-delà, la liste des villes devient trop longue sans recherche.
  static const _searchFrom = 7;

  final _search = TextEditingController();
  late Future<void> _load;
  List<Language> _languages = [];
  List<Country> _countries = [];
  String? _language;
  int? _country, _city;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = AppScope.session(context).user;
    _language = user?.languageCode;
    _country = user?.countryId;
    _city = user?.cityId;
    _load = _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final data = await AppScope.api(context).get('/reference') as Map<String, dynamic>;
    final countries = (data['countries'] as List).map((c) => Country.fromJson(c as Map<String, dynamic>)).toList();

    if (!mounted) return;
    setState(() {
      _languages = (data['languages'] as List).map((l) => Language.fromJson(l as Map<String, dynamic>)).toList();
      _countries = countries;
      if (_languages.length == 1) _language ??= _languages.first.code;
      if (countries.length == 1) _country ??= countries.first.id;
      final cities = _cities;
      if (cities.length == 1) _city ??= cities.first.id;
    });
  }

  List<Named> get _cities {
    for (final c in _countries) {
      if (c.id == _country) return c.cities;
    }
    return const [];
  }

  List<Named> get _visibleCities {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _cities;
    return _cities.where((c) => c.id == _city || c.name.toLowerCase().contains(query)).toList();
  }

  void _pickCountry(int id) {
    if (id == _country) return;
    setState(() {
      _country = id;
      _search.clear();
      final cities = _cities;
      _city = cities.length == 1 ? cities.first.id : null;
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);

    try {
      await AppScope.session(context).updateProfile({'language_code': _language, 'city_id': _city});
      if (widget.fromSettings) navigator.pop();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: widget.fromSettings ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        appBar: widget.fromSettings ? AppBar(title: const Text('Langue, pays et ville')) : null,
        body: FutureBuilder(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SafeArea(
                child: ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _load = _fetch())),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content();
          },
        ),
      ),
    );
  }

  Widget _content() {
    final cities = _visibleCities;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (widget.fromSettings) const SizedBox(height: 4) else const _Hero(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Step(
                          number: 1,
                          title: 'Langue',
                          done: _language != null,
                          children: [
                            for (final language in _languages)
                              _Option(
                                leading: _CodeBadge(language.code.toUpperCase()),
                                label: language.name,
                                selected: language.code == _language,
                                onTap: () => setState(() => _language = language.code),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Step(
                          number: 2,
                          title: 'Pays',
                          done: _country != null,
                          children: [
                            for (final country in _countries)
                              _Option(
                                leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
                                label: country.name,
                                detail: country.dialCode,
                                selected: country.id == _country,
                                onTap: () => _pickCountry(country.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Step(
                          number: 3,
                          title: 'Ville',
                          done: _city != null,
                          children: [
                            if (_country == null) const Muted('Choisissez d\'abord votre pays.'),
                            if (_cities.length >= _searchFrom)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: TextField(
                                  controller: _search,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    hintText: 'Rechercher une ville',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                ),
                              ),
                            for (final city in cities)
                              _Option(
                                leading: Icon(Icons.place_outlined, color: Palette.of(context).link),
                                label: city.name,
                                selected: city.id == _city,
                                onTap: () => setState(() => _city = city.id),
                              ),
                            if (_country != null && cities.isEmpty) const Muted('Aucune ville trouvée.'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _BottomBar(
          child: BusyButton(
            label: widget.fromSettings ? 'Enregistrer' : 'Commencer',
            busy: _busy,
            onPressed: _language != null && _city != null ? _submit : null,
          ),
        ),
      ],
    );
  }
}

/// Bandeau d'accueil : le logo sur le bleu ciel de la marque.
class _Hero extends StatelessWidget {
  const _Hero();

  static const _bottomColor = Color(0xFF63BEE4);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 24, 16, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.sky, _bottomColor],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 488),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: double.infinity),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Palette.onSky.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Image.asset('assets/logo.png', width: 64, height: 64, excludeFromSemantics: true),
              ),
              const SizedBox(height: 18),
              const Text(
                'Où êtes-vous ?',
                style: TextStyle(color: Palette.onSky, fontSize: 28, height: 1.15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ces choix adaptent l\'application et la livraison à votre ville.',
                style: TextStyle(color: Palette.onSky, fontSize: 15, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une étape numérotée, qui passe en coche une fois complétée.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.done, required this.children});

  final int number;
  final String title;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: done ? Palette.sky : p.soft, shape: BoxShape.circle),
                child: done
                    ? const Icon(Icons.check, size: 16, color: Palette.onSky)
                    : Text('$number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.muted)),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.leading, required this.label, required this.selected, required this.onTap, this.detail});

  final Widget leading;
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final radius = BorderRadius.circular(14);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? p.soft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: selected ? p.link : p.line, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 36, child: Center(child: leading)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    if (detail != null) ...[
                      Muted(detail!, size: 13),
                      const SizedBox(width: 10),
                    ],
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 22,
                      color: selected ? p.link : p.line,
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

class _CodeBadge extends StatelessWidget {
  const _CodeBadge(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(8)),
      child: Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.link)),
    );
  }
}

/// Le bouton reste visible, quelle que soit la longueur des listes.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }
}
