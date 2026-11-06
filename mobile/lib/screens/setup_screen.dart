import 'package:flutter/material.dart';

import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';

/// Choix de la langue, du pays et de la ville : au premier lancement et depuis les réglages.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late Future<void> _load;
  List<Language> _languages = [];
  List<Country> _countries = [];
  String? _language;
  int? _country, _city;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = AppScope.session(context).user;
    _language ??= user?.languageCode;
    _country ??= user?.countryId;
    _city ??= user?.cityId;
  }

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<void> _fetch() async {
    final data = await AppScope.api(context).get('/reference') as Map<String, dynamic>;
    final countries = (data['countries'] as List).map((c) => Country.fromJson(c as Map<String, dynamic>)).toList();

    setState(() {
      _languages = (data['languages'] as List).map((l) => Language.fromJson(l as Map<String, dynamic>)).toList();
      _countries = countries;
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

  Widget _choices<T>(String title, List<(T, String)> options, T? selected, ValueChanged<T> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Label(title),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in options)
              ChoiceChip(label: Text(label), selected: value == selected, showCheckmark: false, onSelected: (_) => onPick(value)),
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.fromSettings ? AppBar(title: const Text('Langue, pays et ville')) : null,
      body: SafeArea(
        child: FutureBuilder(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _load = _fetch()));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                if (!widget.fromSettings) ...[
                  const Heading('Où êtes-vous ?'),
                  const SizedBox(height: 8),
                  const Muted('Nous livrons dans les villes proposées ci-dessous.'),
                  const SizedBox(height: 22),
                ],
                _choices('Langue', [for (final l in _languages) (l.code, l.name)], _language, (v) => setState(() => _language = v)),
                _choices('Pays', [for (final c in _countries) (c.id, c.name)], _country, (v) => setState(() {
                  _country = v;
                  _city = null;
                })),
                _choices('Ville', [for (final c in _cities) (c.id, c.name)], _city, (v) => setState(() => _city = v)),
                BusyButton(
                  label: widget.fromSettings ? 'Enregistrer' : 'Commencer',
                  busy: _busy,
                  onPressed: _language != null && _city != null ? _submit : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
