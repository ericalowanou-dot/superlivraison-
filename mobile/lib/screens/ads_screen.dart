import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../state/session.dart';
import '../widgets.dart';
import 'my_ads_screen.dart';
import 'new_ad_screen.dart';

/// Publicités et affiches validées de la ville, à regarder et à partager.
class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> {
  final List<Ad> _ads = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;
  int? _sharing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _ads.isEmpty && _error == null) _fetch(1);
  }

  Future<void> _fetch(int page) async {
    try {
      final data = await AppScope.api(context).get('/ads?page=$page') as Map<String, dynamic>;
      final items = (data['data'] as List).map((a) => Ad.fromJson(a as Map<String, dynamic>));
      final meta = data['meta'] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        if (page == 1) _ads.clear();
        _ads.addAll(items);
        _page = page;
        _hasMore = (meta['current_page'] as int) < (meta['last_page'] as int);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publish() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewAdScreen()));
    if (sent == true && mounted) showMessage(context, 'Affiche envoyée. Elle sera visible après validation.');
  }

  Future<void> _share(Ad ad) async {
    setState(() => _sharing = ad.id);

    try {
      final bytes = await AppScope.api(context).download(ad.imagePath);
      await SharePlus.instance.share(ShareParams(
        text: ad.description == null ? ad.title : '${ad.title}\n${ad.description}',
        files: [XFile.fromData(bytes, name: 'affiche-${ad.id}.jpg', mimeType: 'image/jpeg')],
      ));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sharing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _ads.isEmpty) return ErrorRetry(error: _error!, onRetry: () => _fetch(1));

    return RefreshIndicator(
      onRefresh: () => _fetch(1),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          BusyButton(label: 'Publier une affiche', icon: Icons.add, busy: false, onPressed: _publish),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyAdsScreen())),
            child: const Text('Mes envois'),
          ),
          const SizedBox(height: 20),
          if (_ads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Muted('Aucune publicité dans votre ville pour le moment.', align: TextAlign.center),
            ),
          for (final ad in _ads)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AuthImage(ad.imagePath, fit: BoxFit.fitWidth),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        StatusBadge(ad.categoryLabel),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Partager',
                          icon: _sharing == ad.id
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.share_outlined),
                          onPressed: _sharing == null ? () => _share(ad) : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(ad.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (ad.description != null) ...[
                      const SizedBox(height: 6),
                      Muted(ad.description!),
                    ],
                  ],
                ),
              ),
            ),
          if (_hasMore) OutlinedButton(onPressed: () => _fetch(_page + 1), child: const Text('Voir plus')),
        ],
      ),
    );
  }
}
