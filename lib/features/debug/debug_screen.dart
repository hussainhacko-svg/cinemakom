import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_endpoints.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/repositories/search_repository.dart';

// Developer tool, only reachable in debug builds. Its labels are not
// user-facing, so they are not localized.

/// What one endpoint returned: a count and a few sample lines.
class _ProbeResult {
  const _ProbeResult(this.count, this.samples);

  final int count;
  final List<String> samples;
}

class _Probe {
  _Probe(this.name, this.run);

  final String name;
  final Future<_ProbeResult> Function() run;
  late Future<_ProbeResult> result = run();

  void retry() => result = run();
}

_ProbeResult _items(List<MediaItem> items) => _ProbeResult(items.length, [
  for (final i in items.take(3))
    '${i.id} · ${i.title.en ?? i.title.ar} · ${i.kind?.name ?? '?'}',
]);

_ProbeResult _list<T>(List<T> list, String Function(T) describe) =>
    _ProbeResult(list.length, [for (final x in list.take(3)) describe(x)]);

/// Calls every public endpoint through the repositories and shows what came
/// back. IDs for the detail endpoints come from the latest movie and series.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  late List<_Probe> _probes;

  @override
  void initState() {
    super.initState();
    _probes = _buildProbes();
  }

  List<_Probe> _buildProbes() {
    final catalog = ref.read(catalogRepositoryProvider);
    final search = ref.read(searchRepositoryProvider);
    final media = ref.read(mediaRepositoryProvider);
    const lang = ApiLanguage.en;

    final movie = catalog.latestMovies().then((l) => l.first);
    final series = search
        .advancedSearch(title: 'friends', kind: VideoKind.series)
        .then((l) => l.first);
    final episodes = series.then((s) => media.episodes(s.seriesId));
    final secondEpisode = episodes.then((e) => e.length > 1 ? e[1] : e.first);
    final movieDetails = movie.then((m) => media.details(m.id));
    final languages = catalog.categoryLanguages();

    return [
      _Probe('banners', () async => _items(await catalog.banners())),
      _Probe(
        'videoGroups',
        () async => _list(
          await catalog.videoGroups(lang),
          (g) => '${g.id} · ${g.title} · ${g.items.length} items',
        ),
      ),
      _Probe('videoListPagination', () async {
        final groups = await catalog.videoGroups(lang);
        return _items(await catalog.videoGroupPage(groups.first.id));
      }),
      _Probe('featuredMovies', () async => _items(await catalog.featured())),
      _Probe('latestMovies', () async => _items(await catalog.latestMovies())),
      _Probe('latestSeries', () async => _items(await catalog.latestSeries())),
      _Probe(
        'newlyVideosItems',
        () async => _items(await catalog.newlyAdded()),
      ),
      _Probe(
        'catalog: movies, newest release',
        () async => _items(
          await catalog.catalog(
            kind: VideoKind.movies,
            sort: SortOrder.newestRelease,
          ),
        ),
      ),
      _Probe(
        'catalog: movies, most viewed',
        () async => _items(
          await catalog.catalog(
            kind: VideoKind.movies,
            sort: SortOrder.mostViewed,
          ),
        ),
      ),
      _Probe(
        'catalog: series, recently added',
        () async => _items(
          await catalog.catalog(
            kind: VideoKind.series,
            sort: SortOrder.recentlyAdded,
          ),
        ),
      ),
      _Probe(
        'genres (main + sub)',
        () async =>
            _list(await catalog.genres(lang), (c) => '${c.id} · ${c.name.en}'),
      ),
      _Probe(
        'category',
        () async => _list(
          await catalog.allCategories(),
          (c) => '${c.id} · ${c.name.en} / ${c.name.ar}',
        ),
      ),
      _Probe(
        'categoryLangFreqVideo',
        () async => _list(
          await languages,
          (l) =>
              'cat ${l.categoryId} · ${l.name.en} · '
              '${l.movieCount} movies, ${l.seriesCount} series',
        ),
      ),
      _Probe('videosByCategory (Action)', () async {
        final page = await catalog.videosByCategory(categoryId: '84');
        return _items(page.items);
      }),
      _Probe('videosByCategoryAndLanguage', () async {
        final best = (await languages).reduce(
          (a, b) => a.movieCount >= b.movieCount ? a : b,
        );
        final page = await catalog.videosByCategoryAndLanguage(
          categoryId: best.categoryId,
          languageId: best.languageId,
        );
        return _items(page.items);
      }),
      _Probe(
        'search "batman" (3 sources)',
        () async => _items(await search.search('batman')),
      ),
      _Probe('allVideoInfo (movie)', () async {
        final d = (await movieDetails)!;
        return _ProbeResult(1, [
          '${d.item.title.en} · ${d.item.year} · ${d.item.duration?.inMinutes} min',
          'cast ${d.actors.length}, directors ${d.directors.length}, '
              'writers ${d.writers.length}',
          'intro ${d.introRanges}, subtitles ${d.subtitles.length}',
        ]);
      }),
      _Probe(
        'transcoddedFiles (movie)',
        () async => _list(
          await media.streams((await movie).id),
          (s) =>
              '${s.label} · ${s.container} · expires '
              '${s.expiresAt?.difference(DateTime.now().toUtc()).inHours} h',
        ),
      ),
      _Probe('translationFiles (movie)', () async {
        final tracks = await media.subtitles((await movie).id);
        return _list(tracks, (t) => '${t.languageCode} · ${t.format.name}');
      }),
      _Probe('translationFiles (styled ass, 279230)', () async {
        final tracks = await media.subtitles('279230');
        final styled = tracks.where((t) => t.isStyled).toList();
        return _ProbeResult(styled.length, [
          for (final t in oneTrackPerLanguage(tracks))
            '${t.languageCode} · ${t.format.name}',
        ]);
      }),
      _Probe('videoSeason flags (Lucifer, 36835)', () async {
        final eps = await media.episodes('36835');
        final finales = eps.where((e) => e.numbering.isFinale).toList();
        return _ProbeResult(finales.length, [
          for (final e in finales.take(3)) 'S${e.season} ${e.numbering}',
        ]);
      }),
      _Probe(
        'recommendations (recommend.shabakaty.com)',
        () async => _items(await media.recommendations(await movie)),
      ),
      _Probe('video_thumbnails (most viewed movie)', () async {
        final top = await catalog.catalog(
          kind: VideoKind.movies,
          sort: SortOrder.mostViewed,
        );
        final preview = await media.seekPreview(top.first.id);
        return _ProbeResult(preview?.sheetUrls.length ?? 0, [
          if (preview != null)
            '${top.first.title.en}: ${preview.frameAt(const Duration(minutes: 30))}',
        ]);
      }),
      _Probe('staff (first actor)', () async {
        final actor = (await movieDetails)!.actors.first;
        final page = (await media.staff(actor.id, lang))!;
        return _ProbeResult(page.items.length, [
          '${page.name} · ${page.role}',
          ..._items(page.items).samples,
        ]);
      }),
      _Probe('getVideosByIds (POST)', () async {
        final latest = await catalog.latestMovies();
        return _items(
          await media.byIds([for (final i in latest.take(3)) i.id]),
        );
      }),
      _Probe(
        'videoSeasonNumber (Friends)',
        () async => _list(
          await media.seasons((await series).seriesId),
          (s) => 'season $s',
        ),
      ),
      _Probe(
        'videoSeason (Friends)',
        () async => _list(
          await episodes,
          (Episode e) => 'S${e.season}E${e.episode} · ${e.id}',
        ),
      ),
      _Probe('allVideoInfo (episode)', () async {
        final d = (await media.details((await secondEpisode).id))!;
        return _ProbeResult(1, [
          'S${d.item.season}E${d.item.episode} · series ${d.item.seriesId}',
          'intro ${d.introRanges}',
        ]);
      }),
      _Probe(
        'transcoddedFiles (episode)',
        () async => _list(
          await media.streams((await secondEpisode).id),
          (s) => s.label,
        ),
      ),
      _Probe(
        'faqQuestion',
        () async => _list(await catalog.faq(), (f) => f.question.en ?? ''),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API debug'),
        actions: [
          IconButton(
            tooltip: 'Run all again',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _probes = _buildProbes()),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _probes.length,
        itemBuilder: (context, i) => _ProbeTile(
          key: ObjectKey(_probes[i]),
          probe: _probes[i],
          onRetry: () => setState(_probes[i].retry),
        ),
      ),
    );
  }
}

class _ProbeTile extends StatelessWidget {
  const _ProbeTile({super.key, required this.probe, required this.onRetry});

  final _Probe probe;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<_ProbeResult>(
      future: probe.result,
      builder: (context, snap) {
        final Widget leading;
        final String subtitle;
        if (snap.connectionState != ConnectionState.done) {
          leading = const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
          subtitle = 'loading…';
        } else if (snap.hasError) {
          leading = Icon(Icons.error, color: theme.colorScheme.error);
          subtitle = '${snap.error}';
        } else {
          final r = snap.requireData;
          leading = Icon(
            r.count > 0 ? Icons.check_circle : Icons.remove_circle_outline,
            color: r.count > 0 ? Colors.green : theme.colorScheme.outline,
          );
          subtitle = ['${r.count} result(s)', ...r.samples].join('\n');
        }
        return ListTile(
          leading: leading,
          title: Text(probe.name),
          subtitle: Text(subtitle),
          isThreeLine: subtitle.contains('\n'),
          onTap: onRetry,
        );
      },
    );
  }
}
