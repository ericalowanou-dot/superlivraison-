import 'package:flutter/material.dart';

import '../models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets.dart';

/// Les affiches envoyées par l'utilisateur et leur état de validation.
class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen> {
  List<Ad> _ads = [];
  bool _loading = true;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _ads.isEmpty && _error == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await AppScope.api(context).get('/ads/mine') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _ads = (data['data'] as List).map((a) => Ad.fromJson(a as Map<String, dynamic>)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Ad ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette affiche ?'),
        content: Text(ad.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AppScope.api(context).delete('/ads/${ad.id}');
      await _fetch();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes envois')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _ads.isEmpty
              ? ErrorRetry(error: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      if (_ads.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Muted('Vous n\'avez pas encore envoyé d\'affiche.', align: TextAlign.center),
                        ),
                      for (final ad in _ads)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AuthImage(ad.imagePath, width: 72, height: 72),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(ad.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      StatusBadge(ad.statusLabel, action: ad.status == 'pending'),
                                      if (ad.rejectionReason != null) ...[
                                        const SizedBox(height: 6),
                                        Text(ad.rejectionReason!, style: TextStyle(fontSize: 13, color: p.warn)),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(ad)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
