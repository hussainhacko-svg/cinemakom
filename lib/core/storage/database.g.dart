// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $WatchHistoryTable extends WatchHistory
    with TableInfo<$WatchHistoryTable, WatchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedMeta = const VerificationMeta(
    'finished',
  );
  @override
  late final GeneratedColumn<bool> finished = GeneratedColumn<bool>(
    'finished',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("finished" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleEnMeta = const VerificationMeta(
    'titleEn',
  );
  @override
  late final GeneratedColumn<String> titleEn = GeneratedColumn<String>(
    'title_en',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleArMeta = const VerificationMeta(
    'titleAr',
  );
  @override
  late final GeneratedColumn<String> titleAr = GeneratedColumn<String>(
    'title_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterUrlMeta = const VerificationMeta(
    'posterUrl',
  );
  @override
  late final GeneratedColumn<String> posterUrl = GeneratedColumn<String>(
    'poster_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    videoId,
    seriesId,
    season,
    episode,
    positionMs,
    durationMs,
    finished,
    updatedAt,
    titleEn,
    titleAr,
    posterUrl,
    kind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('finished')) {
      context.handle(
        _finishedMeta,
        finished.isAcceptableOrUnknown(data['finished']!, _finishedMeta),
      );
    } else if (isInserting) {
      context.missing(_finishedMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('title_en')) {
      context.handle(
        _titleEnMeta,
        titleEn.isAcceptableOrUnknown(data['title_en']!, _titleEnMeta),
      );
    }
    if (data.containsKey('title_ar')) {
      context.handle(
        _titleArMeta,
        titleAr.isAcceptableOrUnknown(data['title_ar']!, _titleArMeta),
      );
    }
    if (data.containsKey('poster_url')) {
      context.handle(
        _posterUrlMeta,
        posterUrl.isAcceptableOrUnknown(data['poster_url']!, _posterUrlMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  WatchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchHistoryData(
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      ),
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      ),
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      finished: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}finished'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      titleEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_en'],
      ),
      titleAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_ar'],
      ),
      posterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_url'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
    );
  }

  @override
  $WatchHistoryTable createAlias(String alias) {
    return $WatchHistoryTable(attachedDatabase, alias);
  }
}

class WatchHistoryData extends DataClass
    implements Insertable<WatchHistoryData> {
  /// The movie or episode.
  final String videoId;

  /// The series (its first episode's ID); null for movies.
  final String? seriesId;
  final int? season;
  final int? episode;
  final int positionMs;
  final int durationMs;
  final bool finished;
  final DateTime updatedAt;
  final String? titleEn;
  final String? titleAr;
  final String? posterUrl;

  /// `VideoKind.name`.
  final String? kind;
  const WatchHistoryData({
    required this.videoId,
    this.seriesId,
    this.season,
    this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.finished,
    required this.updatedAt,
    this.titleEn,
    this.titleAr,
    this.posterUrl,
    this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    if (!nullToAbsent || seriesId != null) {
      map['series_id'] = Variable<String>(seriesId);
    }
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<int>(season);
    }
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['finished'] = Variable<bool>(finished);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || titleEn != null) {
      map['title_en'] = Variable<String>(titleEn);
    }
    if (!nullToAbsent || titleAr != null) {
      map['title_ar'] = Variable<String>(titleAr);
    }
    if (!nullToAbsent || posterUrl != null) {
      map['poster_url'] = Variable<String>(posterUrl);
    }
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    return map;
  }

  WatchHistoryCompanion toCompanion(bool nullToAbsent) {
    return WatchHistoryCompanion(
      videoId: Value(videoId),
      seriesId: seriesId == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesId),
      season: season == null && nullToAbsent
          ? const Value.absent()
          : Value(season),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      finished: Value(finished),
      updatedAt: Value(updatedAt),
      titleEn: titleEn == null && nullToAbsent
          ? const Value.absent()
          : Value(titleEn),
      titleAr: titleAr == null && nullToAbsent
          ? const Value.absent()
          : Value(titleAr),
      posterUrl: posterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(posterUrl),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
    );
  }

  factory WatchHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchHistoryData(
      videoId: serializer.fromJson<String>(json['videoId']),
      seriesId: serializer.fromJson<String?>(json['seriesId']),
      season: serializer.fromJson<int?>(json['season']),
      episode: serializer.fromJson<int?>(json['episode']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      finished: serializer.fromJson<bool>(json['finished']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      titleEn: serializer.fromJson<String?>(json['titleEn']),
      titleAr: serializer.fromJson<String?>(json['titleAr']),
      posterUrl: serializer.fromJson<String?>(json['posterUrl']),
      kind: serializer.fromJson<String?>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'seriesId': serializer.toJson<String?>(seriesId),
      'season': serializer.toJson<int?>(season),
      'episode': serializer.toJson<int?>(episode),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'finished': serializer.toJson<bool>(finished),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'titleEn': serializer.toJson<String?>(titleEn),
      'titleAr': serializer.toJson<String?>(titleAr),
      'posterUrl': serializer.toJson<String?>(posterUrl),
      'kind': serializer.toJson<String?>(kind),
    };
  }

  WatchHistoryData copyWith({
    String? videoId,
    Value<String?> seriesId = const Value.absent(),
    Value<int?> season = const Value.absent(),
    Value<int?> episode = const Value.absent(),
    int? positionMs,
    int? durationMs,
    bool? finished,
    DateTime? updatedAt,
    Value<String?> titleEn = const Value.absent(),
    Value<String?> titleAr = const Value.absent(),
    Value<String?> posterUrl = const Value.absent(),
    Value<String?> kind = const Value.absent(),
  }) => WatchHistoryData(
    videoId: videoId ?? this.videoId,
    seriesId: seriesId.present ? seriesId.value : this.seriesId,
    season: season.present ? season.value : this.season,
    episode: episode.present ? episode.value : this.episode,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    finished: finished ?? this.finished,
    updatedAt: updatedAt ?? this.updatedAt,
    titleEn: titleEn.present ? titleEn.value : this.titleEn,
    titleAr: titleAr.present ? titleAr.value : this.titleAr,
    posterUrl: posterUrl.present ? posterUrl.value : this.posterUrl,
    kind: kind.present ? kind.value : this.kind,
  );
  WatchHistoryData copyWithCompanion(WatchHistoryCompanion data) {
    return WatchHistoryData(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      season: data.season.present ? data.season.value : this.season,
      episode: data.episode.present ? data.episode.value : this.episode,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      finished: data.finished.present ? data.finished.value : this.finished,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      titleEn: data.titleEn.present ? data.titleEn.value : this.titleEn,
      titleAr: data.titleAr.present ? data.titleAr.value : this.titleAr,
      posterUrl: data.posterUrl.present ? data.posterUrl.value : this.posterUrl,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoryData(')
          ..write('videoId: $videoId, ')
          ..write('seriesId: $seriesId, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('finished: $finished, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('titleEn: $titleEn, ')
          ..write('titleAr: $titleAr, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    videoId,
    seriesId,
    season,
    episode,
    positionMs,
    durationMs,
    finished,
    updatedAt,
    titleEn,
    titleAr,
    posterUrl,
    kind,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchHistoryData &&
          other.videoId == this.videoId &&
          other.seriesId == this.seriesId &&
          other.season == this.season &&
          other.episode == this.episode &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.finished == this.finished &&
          other.updatedAt == this.updatedAt &&
          other.titleEn == this.titleEn &&
          other.titleAr == this.titleAr &&
          other.posterUrl == this.posterUrl &&
          other.kind == this.kind);
}

class WatchHistoryCompanion extends UpdateCompanion<WatchHistoryData> {
  final Value<String> videoId;
  final Value<String?> seriesId;
  final Value<int?> season;
  final Value<int?> episode;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<bool> finished;
  final Value<DateTime> updatedAt;
  final Value<String?> titleEn;
  final Value<String?> titleAr;
  final Value<String?> posterUrl;
  final Value<String?> kind;
  final Value<int> rowid;
  const WatchHistoryCompanion({
    this.videoId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.finished = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.titleEn = const Value.absent(),
    this.titleAr = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchHistoryCompanion.insert({
    required String videoId,
    this.seriesId = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    required int positionMs,
    required int durationMs,
    required bool finished,
    required DateTime updatedAt,
    this.titleEn = const Value.absent(),
    this.titleAr = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : videoId = Value(videoId),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs),
       finished = Value(finished),
       updatedAt = Value(updatedAt);
  static Insertable<WatchHistoryData> custom({
    Expression<String>? videoId,
    Expression<String>? seriesId,
    Expression<int>? season,
    Expression<int>? episode,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<bool>? finished,
    Expression<DateTime>? updatedAt,
    Expression<String>? titleEn,
    Expression<String>? titleAr,
    Expression<String>? posterUrl,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (seriesId != null) 'series_id': seriesId,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (finished != null) 'finished': finished,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (titleEn != null) 'title_en': titleEn,
      if (titleAr != null) 'title_ar': titleAr,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchHistoryCompanion copyWith({
    Value<String>? videoId,
    Value<String?>? seriesId,
    Value<int?>? season,
    Value<int?>? episode,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<bool>? finished,
    Value<DateTime>? updatedAt,
    Value<String?>? titleEn,
    Value<String?>? titleAr,
    Value<String?>? posterUrl,
    Value<String?>? kind,
    Value<int>? rowid,
  }) {
    return WatchHistoryCompanion(
      videoId: videoId ?? this.videoId,
      seriesId: seriesId ?? this.seriesId,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      finished: finished ?? this.finished,
      updatedAt: updatedAt ?? this.updatedAt,
      titleEn: titleEn ?? this.titleEn,
      titleAr: titleAr ?? this.titleAr,
      posterUrl: posterUrl ?? this.posterUrl,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (finished.present) {
      map['finished'] = Variable<bool>(finished.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (titleEn.present) {
      map['title_en'] = Variable<String>(titleEn.value);
    }
    if (titleAr.present) {
      map['title_ar'] = Variable<String>(titleAr.value);
    }
    if (posterUrl.present) {
      map['poster_url'] = Variable<String>(posterUrl.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoryCompanion(')
          ..write('videoId: $videoId, ')
          ..write('seriesId: $seriesId, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('finished: $finished, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('titleEn: $titleEn, ')
          ..write('titleAr: $titleAr, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, FavoriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _titleIdMeta = const VerificationMeta(
    'titleId',
  );
  @override
  late final GeneratedColumn<String> titleId = GeneratedColumn<String>(
    'title_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleEnMeta = const VerificationMeta(
    'titleEn',
  );
  @override
  late final GeneratedColumn<String> titleEn = GeneratedColumn<String>(
    'title_en',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleArMeta = const VerificationMeta(
    'titleAr',
  );
  @override
  late final GeneratedColumn<String> titleAr = GeneratedColumn<String>(
    'title_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterUrlMeta = const VerificationMeta(
    'posterUrl',
  );
  @override
  late final GeneratedColumn<String> posterUrl = GeneratedColumn<String>(
    'poster_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreEnMeta = const VerificationMeta(
    'genreEn',
  );
  @override
  late final GeneratedColumn<String> genreEn = GeneratedColumn<String>(
    'genre_en',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreArMeta = const VerificationMeta(
    'genreAr',
  );
  @override
  late final GeneratedColumn<String> genreAr = GeneratedColumn<String>(
    'genre_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    titleId,
    titleEn,
    titleAr,
    posterUrl,
    kind,
    year,
    genreEn,
    genreAr,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('title_id')) {
      context.handle(
        _titleIdMeta,
        titleId.isAcceptableOrUnknown(data['title_id']!, _titleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_titleIdMeta);
    }
    if (data.containsKey('title_en')) {
      context.handle(
        _titleEnMeta,
        titleEn.isAcceptableOrUnknown(data['title_en']!, _titleEnMeta),
      );
    }
    if (data.containsKey('title_ar')) {
      context.handle(
        _titleArMeta,
        titleAr.isAcceptableOrUnknown(data['title_ar']!, _titleArMeta),
      );
    }
    if (data.containsKey('poster_url')) {
      context.handle(
        _posterUrlMeta,
        posterUrl.isAcceptableOrUnknown(data['poster_url']!, _posterUrlMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('genre_en')) {
      context.handle(
        _genreEnMeta,
        genreEn.isAcceptableOrUnknown(data['genre_en']!, _genreEnMeta),
      );
    }
    if (data.containsKey('genre_ar')) {
      context.handle(
        _genreArMeta,
        genreAr.isAcceptableOrUnknown(data['genre_ar']!, _genreArMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {titleId};
  @override
  FavoriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteRow(
      titleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_id'],
      )!,
      titleEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_en'],
      ),
      titleAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_ar'],
      ),
      posterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_url'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      genreEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre_en'],
      ),
      genreAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre_ar'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class FavoriteRow extends DataClass implements Insertable<FavoriteRow> {
  /// The movie, or the series (its first episode's ID).
  final String titleId;
  final String? titleEn;
  final String? titleAr;
  final String? posterUrl;

  /// `VideoKind.name`.
  final String? kind;
  final int? year;

  /// The first genre, for the card's caption.
  final String? genreEn;
  final String? genreAr;
  final DateTime addedAt;
  const FavoriteRow({
    required this.titleId,
    this.titleEn,
    this.titleAr,
    this.posterUrl,
    this.kind,
    this.year,
    this.genreEn,
    this.genreAr,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['title_id'] = Variable<String>(titleId);
    if (!nullToAbsent || titleEn != null) {
      map['title_en'] = Variable<String>(titleEn);
    }
    if (!nullToAbsent || titleAr != null) {
      map['title_ar'] = Variable<String>(titleAr);
    }
    if (!nullToAbsent || posterUrl != null) {
      map['poster_url'] = Variable<String>(posterUrl);
    }
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || genreEn != null) {
      map['genre_en'] = Variable<String>(genreEn);
    }
    if (!nullToAbsent || genreAr != null) {
      map['genre_ar'] = Variable<String>(genreAr);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      titleId: Value(titleId),
      titleEn: titleEn == null && nullToAbsent
          ? const Value.absent()
          : Value(titleEn),
      titleAr: titleAr == null && nullToAbsent
          ? const Value.absent()
          : Value(titleAr),
      posterUrl: posterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(posterUrl),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      genreEn: genreEn == null && nullToAbsent
          ? const Value.absent()
          : Value(genreEn),
      genreAr: genreAr == null && nullToAbsent
          ? const Value.absent()
          : Value(genreAr),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteRow(
      titleId: serializer.fromJson<String>(json['titleId']),
      titleEn: serializer.fromJson<String?>(json['titleEn']),
      titleAr: serializer.fromJson<String?>(json['titleAr']),
      posterUrl: serializer.fromJson<String?>(json['posterUrl']),
      kind: serializer.fromJson<String?>(json['kind']),
      year: serializer.fromJson<int?>(json['year']),
      genreEn: serializer.fromJson<String?>(json['genreEn']),
      genreAr: serializer.fromJson<String?>(json['genreAr']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'titleId': serializer.toJson<String>(titleId),
      'titleEn': serializer.toJson<String?>(titleEn),
      'titleAr': serializer.toJson<String?>(titleAr),
      'posterUrl': serializer.toJson<String?>(posterUrl),
      'kind': serializer.toJson<String?>(kind),
      'year': serializer.toJson<int?>(year),
      'genreEn': serializer.toJson<String?>(genreEn),
      'genreAr': serializer.toJson<String?>(genreAr),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteRow copyWith({
    String? titleId,
    Value<String?> titleEn = const Value.absent(),
    Value<String?> titleAr = const Value.absent(),
    Value<String?> posterUrl = const Value.absent(),
    Value<String?> kind = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> genreEn = const Value.absent(),
    Value<String?> genreAr = const Value.absent(),
    DateTime? addedAt,
  }) => FavoriteRow(
    titleId: titleId ?? this.titleId,
    titleEn: titleEn.present ? titleEn.value : this.titleEn,
    titleAr: titleAr.present ? titleAr.value : this.titleAr,
    posterUrl: posterUrl.present ? posterUrl.value : this.posterUrl,
    kind: kind.present ? kind.value : this.kind,
    year: year.present ? year.value : this.year,
    genreEn: genreEn.present ? genreEn.value : this.genreEn,
    genreAr: genreAr.present ? genreAr.value : this.genreAr,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoriteRow copyWithCompanion(FavoritesCompanion data) {
    return FavoriteRow(
      titleId: data.titleId.present ? data.titleId.value : this.titleId,
      titleEn: data.titleEn.present ? data.titleEn.value : this.titleEn,
      titleAr: data.titleAr.present ? data.titleAr.value : this.titleAr,
      posterUrl: data.posterUrl.present ? data.posterUrl.value : this.posterUrl,
      kind: data.kind.present ? data.kind.value : this.kind,
      year: data.year.present ? data.year.value : this.year,
      genreEn: data.genreEn.present ? data.genreEn.value : this.genreEn,
      genreAr: data.genreAr.present ? data.genreAr.value : this.genreAr,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRow(')
          ..write('titleId: $titleId, ')
          ..write('titleEn: $titleEn, ')
          ..write('titleAr: $titleAr, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('kind: $kind, ')
          ..write('year: $year, ')
          ..write('genreEn: $genreEn, ')
          ..write('genreAr: $genreAr, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    titleId,
    titleEn,
    titleAr,
    posterUrl,
    kind,
    year,
    genreEn,
    genreAr,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteRow &&
          other.titleId == this.titleId &&
          other.titleEn == this.titleEn &&
          other.titleAr == this.titleAr &&
          other.posterUrl == this.posterUrl &&
          other.kind == this.kind &&
          other.year == this.year &&
          other.genreEn == this.genreEn &&
          other.genreAr == this.genreAr &&
          other.addedAt == this.addedAt);
}

class FavoritesCompanion extends UpdateCompanion<FavoriteRow> {
  final Value<String> titleId;
  final Value<String?> titleEn;
  final Value<String?> titleAr;
  final Value<String?> posterUrl;
  final Value<String?> kind;
  final Value<int?> year;
  final Value<String?> genreEn;
  final Value<String?> genreAr;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.titleId = const Value.absent(),
    this.titleEn = const Value.absent(),
    this.titleAr = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.kind = const Value.absent(),
    this.year = const Value.absent(),
    this.genreEn = const Value.absent(),
    this.genreAr = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String titleId,
    this.titleEn = const Value.absent(),
    this.titleAr = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.kind = const Value.absent(),
    this.year = const Value.absent(),
    this.genreEn = const Value.absent(),
    this.genreAr = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : titleId = Value(titleId),
       addedAt = Value(addedAt);
  static Insertable<FavoriteRow> custom({
    Expression<String>? titleId,
    Expression<String>? titleEn,
    Expression<String>? titleAr,
    Expression<String>? posterUrl,
    Expression<String>? kind,
    Expression<int>? year,
    Expression<String>? genreEn,
    Expression<String>? genreAr,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (titleId != null) 'title_id': titleId,
      if (titleEn != null) 'title_en': titleEn,
      if (titleAr != null) 'title_ar': titleAr,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (kind != null) 'kind': kind,
      if (year != null) 'year': year,
      if (genreEn != null) 'genre_en': genreEn,
      if (genreAr != null) 'genre_ar': genreAr,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<String>? titleId,
    Value<String?>? titleEn,
    Value<String?>? titleAr,
    Value<String?>? posterUrl,
    Value<String?>? kind,
    Value<int?>? year,
    Value<String?>? genreEn,
    Value<String?>? genreAr,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      titleId: titleId ?? this.titleId,
      titleEn: titleEn ?? this.titleEn,
      titleAr: titleAr ?? this.titleAr,
      posterUrl: posterUrl ?? this.posterUrl,
      kind: kind ?? this.kind,
      year: year ?? this.year,
      genreEn: genreEn ?? this.genreEn,
      genreAr: genreAr ?? this.genreAr,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (titleId.present) {
      map['title_id'] = Variable<String>(titleId.value);
    }
    if (titleEn.present) {
      map['title_en'] = Variable<String>(titleEn.value);
    }
    if (titleAr.present) {
      map['title_ar'] = Variable<String>(titleAr.value);
    }
    if (posterUrl.present) {
      map['poster_url'] = Variable<String>(posterUrl.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (genreEn.present) {
      map['genre_en'] = Variable<String>(genreEn.value);
    }
    if (genreAr.present) {
      map['genre_ar'] = Variable<String>(genreAr.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('titleId: $titleId, ')
          ..write('titleEn: $titleEn, ')
          ..write('titleAr: $titleAr, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('kind: $kind, ')
          ..write('year: $year, ')
          ..write('genreEn: $genreEn, ')
          ..write('genreAr: $genreAr, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContinueHiddenTable extends ContinueHidden
    with TableInfo<$ContinueHiddenTable, HiddenContinueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContinueHiddenTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _titleIdMeta = const VerificationMeta(
    'titleId',
  );
  @override
  late final GeneratedColumn<String> titleId = GeneratedColumn<String>(
    'title_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hiddenAtMeta = const VerificationMeta(
    'hiddenAt',
  );
  @override
  late final GeneratedColumn<DateTime> hiddenAt = GeneratedColumn<DateTime>(
    'hidden_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [titleId, hiddenAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'continue_hidden';
  @override
  VerificationContext validateIntegrity(
    Insertable<HiddenContinueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('title_id')) {
      context.handle(
        _titleIdMeta,
        titleId.isAcceptableOrUnknown(data['title_id']!, _titleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_titleIdMeta);
    }
    if (data.containsKey('hidden_at')) {
      context.handle(
        _hiddenAtMeta,
        hiddenAt.isAcceptableOrUnknown(data['hidden_at']!, _hiddenAtMeta),
      );
    } else if (isInserting) {
      context.missing(_hiddenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {titleId};
  @override
  HiddenContinueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HiddenContinueRow(
      titleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_id'],
      )!,
      hiddenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hidden_at'],
      )!,
    );
  }

  @override
  $ContinueHiddenTable createAlias(String alias) {
    return $ContinueHiddenTable(attachedDatabase, alias);
  }
}

class HiddenContinueRow extends DataClass
    implements Insertable<HiddenContinueRow> {
  /// The movie, or the series.
  final String titleId;
  final DateTime hiddenAt;
  const HiddenContinueRow({required this.titleId, required this.hiddenAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['title_id'] = Variable<String>(titleId);
    map['hidden_at'] = Variable<DateTime>(hiddenAt);
    return map;
  }

  ContinueHiddenCompanion toCompanion(bool nullToAbsent) {
    return ContinueHiddenCompanion(
      titleId: Value(titleId),
      hiddenAt: Value(hiddenAt),
    );
  }

  factory HiddenContinueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HiddenContinueRow(
      titleId: serializer.fromJson<String>(json['titleId']),
      hiddenAt: serializer.fromJson<DateTime>(json['hiddenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'titleId': serializer.toJson<String>(titleId),
      'hiddenAt': serializer.toJson<DateTime>(hiddenAt),
    };
  }

  HiddenContinueRow copyWith({String? titleId, DateTime? hiddenAt}) =>
      HiddenContinueRow(
        titleId: titleId ?? this.titleId,
        hiddenAt: hiddenAt ?? this.hiddenAt,
      );
  HiddenContinueRow copyWithCompanion(ContinueHiddenCompanion data) {
    return HiddenContinueRow(
      titleId: data.titleId.present ? data.titleId.value : this.titleId,
      hiddenAt: data.hiddenAt.present ? data.hiddenAt.value : this.hiddenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HiddenContinueRow(')
          ..write('titleId: $titleId, ')
          ..write('hiddenAt: $hiddenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(titleId, hiddenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HiddenContinueRow &&
          other.titleId == this.titleId &&
          other.hiddenAt == this.hiddenAt);
}

class ContinueHiddenCompanion extends UpdateCompanion<HiddenContinueRow> {
  final Value<String> titleId;
  final Value<DateTime> hiddenAt;
  final Value<int> rowid;
  const ContinueHiddenCompanion({
    this.titleId = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContinueHiddenCompanion.insert({
    required String titleId,
    required DateTime hiddenAt,
    this.rowid = const Value.absent(),
  }) : titleId = Value(titleId),
       hiddenAt = Value(hiddenAt);
  static Insertable<HiddenContinueRow> custom({
    Expression<String>? titleId,
    Expression<DateTime>? hiddenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (titleId != null) 'title_id': titleId,
      if (hiddenAt != null) 'hidden_at': hiddenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContinueHiddenCompanion copyWith({
    Value<String>? titleId,
    Value<DateTime>? hiddenAt,
    Value<int>? rowid,
  }) {
    return ContinueHiddenCompanion(
      titleId: titleId ?? this.titleId,
      hiddenAt: hiddenAt ?? this.hiddenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (titleId.present) {
      map['title_id'] = Variable<String>(titleId.value);
    }
    if (hiddenAt.present) {
      map['hidden_at'] = Variable<DateTime>(hiddenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContinueHiddenCompanion(')
          ..write('titleId: $titleId, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadsTable extends Downloads
    with TableInfo<$DownloadsTable, DownloadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleIdMeta = const VerificationMeta(
    'titleId',
  );
  @override
  late final GeneratedColumn<String> titleId = GeneratedColumn<String>(
    'title_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeLastMeta = const VerificationMeta(
    'episodeLast',
  );
  @override
  late final GeneratedColumn<int> episodeLast = GeneratedColumn<int>(
    'episode_last',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finaleMeta = const VerificationMeta('finale');
  @override
  late final GeneratedColumn<bool> finale = GeneratedColumn<bool>(
    'finale',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("finale" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _titleEnMeta = const VerificationMeta(
    'titleEn',
  );
  @override
  late final GeneratedColumn<String> titleEn = GeneratedColumn<String>(
    'title_en',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleArMeta = const VerificationMeta(
    'titleAr',
  );
  @override
  late final GeneratedColumn<String> titleAr = GeneratedColumn<String>(
    'title_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterUrlMeta = const VerificationMeta(
    'posterUrl',
  );
  @override
  late final GeneratedColumn<String> posterUrl = GeneratedColumn<String>(
    'poster_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
    'quality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseDirectoryMeta = const VerificationMeta(
    'baseDirectory',
  );
  @override
  late final GeneratedColumn<String> baseDirectory = GeneratedColumn<String>(
    'base_directory',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtitlesMeta = const VerificationMeta(
    'subtitles',
  );
  @override
  late final GeneratedColumn<String> subtitles = GeneratedColumn<String>(
    'subtitles',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _problemMeta = const VerificationMeta(
    'problem',
  );
  @override
  late final GeneratedColumn<String> problem = GeneratedColumn<String>(
    'problem',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    videoId,
    titleId,
    season,
    episode,
    episodeLast,
    finale,
    titleEn,
    titleAr,
    posterUrl,
    kind,
    year,
    durationMs,
    quality,
    baseDirectory,
    directory,
    fileName,
    subtitles,
    totalBytes,
    status,
    problem,
    addedAt,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('title_id')) {
      context.handle(
        _titleIdMeta,
        titleId.isAcceptableOrUnknown(data['title_id']!, _titleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_titleIdMeta);
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('episode_last')) {
      context.handle(
        _episodeLastMeta,
        episodeLast.isAcceptableOrUnknown(
          data['episode_last']!,
          _episodeLastMeta,
        ),
      );
    }
    if (data.containsKey('finale')) {
      context.handle(
        _finaleMeta,
        finale.isAcceptableOrUnknown(data['finale']!, _finaleMeta),
      );
    }
    if (data.containsKey('title_en')) {
      context.handle(
        _titleEnMeta,
        titleEn.isAcceptableOrUnknown(data['title_en']!, _titleEnMeta),
      );
    }
    if (data.containsKey('title_ar')) {
      context.handle(
        _titleArMeta,
        titleAr.isAcceptableOrUnknown(data['title_ar']!, _titleArMeta),
      );
    }
    if (data.containsKey('poster_url')) {
      context.handle(
        _posterUrlMeta,
        posterUrl.isAcceptableOrUnknown(data['poster_url']!, _posterUrlMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('base_directory')) {
      context.handle(
        _baseDirectoryMeta,
        baseDirectory.isAcceptableOrUnknown(
          data['base_directory']!,
          _baseDirectoryMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseDirectoryMeta);
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    } else if (isInserting) {
      context.missing(_directoryMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('subtitles')) {
      context.handle(
        _subtitlesMeta,
        subtitles.isAcceptableOrUnknown(data['subtitles']!, _subtitlesMeta),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('problem')) {
      context.handle(
        _problemMeta,
        problem.isAcceptableOrUnknown(data['problem']!, _problemMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoId};
  @override
  DownloadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadRow(
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
      titleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_id'],
      )!,
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      ),
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      ),
      episodeLast: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_last'],
      ),
      finale: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}finale'],
      )!,
      titleEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_en'],
      ),
      titleAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_ar'],
      ),
      posterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_url'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality'],
      )!,
      baseDirectory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_directory'],
      )!,
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      subtitles: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitles'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      problem: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}problem'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $DownloadsTable createAlias(String alias) {
    return $DownloadsTable(attachedDatabase, alias);
  }
}

class DownloadRow extends DataClass implements Insertable<DownloadRow> {
  /// The movie or episode; also the downloader's task ID.
  final String videoId;

  /// The movie, or the series (its first episode's ID).
  final String titleId;
  final int? season;

  /// The server's `episodeNummer`, and the last number of a double episode.
  final int? episode;
  final int? episodeLast;
  final bool finale;
  final String? titleEn;
  final String? titleAr;
  final String? posterUrl;

  /// `VideoKind.name`.
  final String? kind;
  final int? year;
  final int? durationMs;

  /// The stream's resolution, e.g. "1080p".
  final String quality;

  /// background_downloader's `BaseDirectory.name`, the folder and the file.
  final String baseDirectory;
  final String directory;
  final String fileName;

  /// The subtitle files beside the video, as JSON:
  /// `[{"lang": "ar", "file": "….ar.srt", "format": "srt"}]`.
  final String subtitles;
  final int? totalBytes;

  /// `DownloadStatus.name`.
  final String status;

  /// Why it failed (`DownloadProblem.name`), when it did.
  final String? problem;
  final DateTime addedAt;
  final DateTime? completedAt;
  const DownloadRow({
    required this.videoId,
    required this.titleId,
    this.season,
    this.episode,
    this.episodeLast,
    required this.finale,
    this.titleEn,
    this.titleAr,
    this.posterUrl,
    this.kind,
    this.year,
    this.durationMs,
    required this.quality,
    required this.baseDirectory,
    required this.directory,
    required this.fileName,
    required this.subtitles,
    this.totalBytes,
    required this.status,
    this.problem,
    required this.addedAt,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_id'] = Variable<String>(videoId);
    map['title_id'] = Variable<String>(titleId);
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<int>(season);
    }
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    if (!nullToAbsent || episodeLast != null) {
      map['episode_last'] = Variable<int>(episodeLast);
    }
    map['finale'] = Variable<bool>(finale);
    if (!nullToAbsent || titleEn != null) {
      map['title_en'] = Variable<String>(titleEn);
    }
    if (!nullToAbsent || titleAr != null) {
      map['title_ar'] = Variable<String>(titleAr);
    }
    if (!nullToAbsent || posterUrl != null) {
      map['poster_url'] = Variable<String>(posterUrl);
    }
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['quality'] = Variable<String>(quality);
    map['base_directory'] = Variable<String>(baseDirectory);
    map['directory'] = Variable<String>(directory);
    map['file_name'] = Variable<String>(fileName);
    map['subtitles'] = Variable<String>(subtitles);
    if (!nullToAbsent || totalBytes != null) {
      map['total_bytes'] = Variable<int>(totalBytes);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || problem != null) {
      map['problem'] = Variable<String>(problem);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  DownloadsCompanion toCompanion(bool nullToAbsent) {
    return DownloadsCompanion(
      videoId: Value(videoId),
      titleId: Value(titleId),
      season: season == null && nullToAbsent
          ? const Value.absent()
          : Value(season),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      episodeLast: episodeLast == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeLast),
      finale: Value(finale),
      titleEn: titleEn == null && nullToAbsent
          ? const Value.absent()
          : Value(titleEn),
      titleAr: titleAr == null && nullToAbsent
          ? const Value.absent()
          : Value(titleAr),
      posterUrl: posterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(posterUrl),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      quality: Value(quality),
      baseDirectory: Value(baseDirectory),
      directory: Value(directory),
      fileName: Value(fileName),
      subtitles: Value(subtitles),
      totalBytes: totalBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalBytes),
      status: Value(status),
      problem: problem == null && nullToAbsent
          ? const Value.absent()
          : Value(problem),
      addedAt: Value(addedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory DownloadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadRow(
      videoId: serializer.fromJson<String>(json['videoId']),
      titleId: serializer.fromJson<String>(json['titleId']),
      season: serializer.fromJson<int?>(json['season']),
      episode: serializer.fromJson<int?>(json['episode']),
      episodeLast: serializer.fromJson<int?>(json['episodeLast']),
      finale: serializer.fromJson<bool>(json['finale']),
      titleEn: serializer.fromJson<String?>(json['titleEn']),
      titleAr: serializer.fromJson<String?>(json['titleAr']),
      posterUrl: serializer.fromJson<String?>(json['posterUrl']),
      kind: serializer.fromJson<String?>(json['kind']),
      year: serializer.fromJson<int?>(json['year']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      quality: serializer.fromJson<String>(json['quality']),
      baseDirectory: serializer.fromJson<String>(json['baseDirectory']),
      directory: serializer.fromJson<String>(json['directory']),
      fileName: serializer.fromJson<String>(json['fileName']),
      subtitles: serializer.fromJson<String>(json['subtitles']),
      totalBytes: serializer.fromJson<int?>(json['totalBytes']),
      status: serializer.fromJson<String>(json['status']),
      problem: serializer.fromJson<String?>(json['problem']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoId': serializer.toJson<String>(videoId),
      'titleId': serializer.toJson<String>(titleId),
      'season': serializer.toJson<int?>(season),
      'episode': serializer.toJson<int?>(episode),
      'episodeLast': serializer.toJson<int?>(episodeLast),
      'finale': serializer.toJson<bool>(finale),
      'titleEn': serializer.toJson<String?>(titleEn),
      'titleAr': serializer.toJson<String?>(titleAr),
      'posterUrl': serializer.toJson<String?>(posterUrl),
      'kind': serializer.toJson<String?>(kind),
      'year': serializer.toJson<int?>(year),
      'durationMs': serializer.toJson<int?>(durationMs),
      'quality': serializer.toJson<String>(quality),
      'baseDirectory': serializer.toJson<String>(baseDirectory),
      'directory': serializer.toJson<String>(directory),
      'fileName': serializer.toJson<String>(fileName),
      'subtitles': serializer.toJson<String>(subtitles),
      'totalBytes': serializer.toJson<int?>(totalBytes),
      'status': serializer.toJson<String>(status),
      'problem': serializer.toJson<String?>(problem),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  DownloadRow copyWith({
    String? videoId,
    String? titleId,
    Value<int?> season = const Value.absent(),
    Value<int?> episode = const Value.absent(),
    Value<int?> episodeLast = const Value.absent(),
    bool? finale,
    Value<String?> titleEn = const Value.absent(),
    Value<String?> titleAr = const Value.absent(),
    Value<String?> posterUrl = const Value.absent(),
    Value<String?> kind = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    String? quality,
    String? baseDirectory,
    String? directory,
    String? fileName,
    String? subtitles,
    Value<int?> totalBytes = const Value.absent(),
    String? status,
    Value<String?> problem = const Value.absent(),
    DateTime? addedAt,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => DownloadRow(
    videoId: videoId ?? this.videoId,
    titleId: titleId ?? this.titleId,
    season: season.present ? season.value : this.season,
    episode: episode.present ? episode.value : this.episode,
    episodeLast: episodeLast.present ? episodeLast.value : this.episodeLast,
    finale: finale ?? this.finale,
    titleEn: titleEn.present ? titleEn.value : this.titleEn,
    titleAr: titleAr.present ? titleAr.value : this.titleAr,
    posterUrl: posterUrl.present ? posterUrl.value : this.posterUrl,
    kind: kind.present ? kind.value : this.kind,
    year: year.present ? year.value : this.year,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    quality: quality ?? this.quality,
    baseDirectory: baseDirectory ?? this.baseDirectory,
    directory: directory ?? this.directory,
    fileName: fileName ?? this.fileName,
    subtitles: subtitles ?? this.subtitles,
    totalBytes: totalBytes.present ? totalBytes.value : this.totalBytes,
    status: status ?? this.status,
    problem: problem.present ? problem.value : this.problem,
    addedAt: addedAt ?? this.addedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  DownloadRow copyWithCompanion(DownloadsCompanion data) {
    return DownloadRow(
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      titleId: data.titleId.present ? data.titleId.value : this.titleId,
      season: data.season.present ? data.season.value : this.season,
      episode: data.episode.present ? data.episode.value : this.episode,
      episodeLast: data.episodeLast.present
          ? data.episodeLast.value
          : this.episodeLast,
      finale: data.finale.present ? data.finale.value : this.finale,
      titleEn: data.titleEn.present ? data.titleEn.value : this.titleEn,
      titleAr: data.titleAr.present ? data.titleAr.value : this.titleAr,
      posterUrl: data.posterUrl.present ? data.posterUrl.value : this.posterUrl,
      kind: data.kind.present ? data.kind.value : this.kind,
      year: data.year.present ? data.year.value : this.year,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      quality: data.quality.present ? data.quality.value : this.quality,
      baseDirectory: data.baseDirectory.present
          ? data.baseDirectory.value
          : this.baseDirectory,
      directory: data.directory.present ? data.directory.value : this.directory,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      subtitles: data.subtitles.present ? data.subtitles.value : this.subtitles,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      status: data.status.present ? data.status.value : this.status,
      problem: data.problem.present ? data.problem.value : this.problem,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadRow(')
          ..write('videoId: $videoId, ')
          ..write('titleId: $titleId, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('episodeLast: $episodeLast, ')
          ..write('finale: $finale, ')
          ..write('titleEn: $titleEn, ')
          ..write('titleAr: $titleAr, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('kind: $kind, ')
          ..write('year: $year, ')
          ..write('durationMs: $durationMs, ')
          ..write('quality: $quality, ')
          ..write('baseDirectory: $baseDirectory, ')
          ..write('directory: $directory, ')
          ..write('fileName: $fileName, ')
          ..write('subtitles: $subtitles, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('status: $status, ')
          ..write('problem: $problem, ')
          ..write('addedAt: $addedAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    videoId,
    titleId,
    season,
    episode,
    episodeLast,
    finale,
    titleEn,
    titleAr,
    posterUrl,
    kind,
    year,
    durationMs,
    quality,
    baseDirectory,
    directory,
    fileName,
    subtitles,
    totalBytes,
    status,
    problem,
    addedAt,
    completedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadRow &&
          other.videoId == this.videoId &&
          other.titleId == this.titleId &&
          other.season == this.season &&
          other.episode == this.episode &&
          other.episodeLast == this.episodeLast &&
          other.finale == this.finale &&
          other.titleEn == this.titleEn &&
          other.titleAr == this.titleAr &&
          other.posterUrl == this.posterUrl &&
          other.kind == this.kind &&
          other.year == this.year &&
          other.durationMs == this.durationMs &&
          other.quality == this.quality &&
          other.baseDirectory == this.baseDirectory &&
          other.directory == this.directory &&
          other.fileName == this.fileName &&
          other.subtitles == this.subtitles &&
          other.totalBytes == this.totalBytes &&
          other.status == this.status &&
          other.problem == this.problem &&
          other.addedAt == this.addedAt &&
          other.completedAt == this.completedAt);
}

class DownloadsCompanion extends UpdateCompanion<DownloadRow> {
  final Value<String> videoId;
  final Value<String> titleId;
  final Value<int?> season;
  final Value<int?> episode;
  final Value<int?> episodeLast;
  final Value<bool> finale;
  final Value<String?> titleEn;
  final Value<String?> titleAr;
  final Value<String?> posterUrl;
  final Value<String?> kind;
  final Value<int?> year;
  final Value<int?> durationMs;
  final Value<String> quality;
  final Value<String> baseDirectory;
  final Value<String> directory;
  final Value<String> fileName;
  final Value<String> subtitles;
  final Value<int?> totalBytes;
  final Value<String> status;
  final Value<String?> problem;
  final Value<DateTime> addedAt;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const DownloadsCompanion({
    this.videoId = const Value.absent(),
    this.titleId = const Value.absent(),
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.episodeLast = const Value.absent(),
    this.finale = const Value.absent(),
    this.titleEn = const Value.absent(),
    this.titleAr = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.kind = const Value.absent(),
    this.year = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.quality = const Value.absent(),
    this.baseDirectory = const Value.absent(),
    this.directory = const Value.absent(),
    this.fileName = const Value.absent(),
    this.subtitles = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.problem = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsCompanion.insert({
    required String videoId,
    required String titleId,
    this.season = const Value.absent(),
    this.episode = const Value.absent(),
    this.episodeLast = const Value.absent(),
    this.finale = const Value.absent(),
    this.titleEn = const Value.absent(),
    this.titleAr = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.kind = const Value.absent(),
    this.year = const Value.absent(),
    this.durationMs = const Value.absent(),
    required String quality,
    required String baseDirectory,
    required String directory,
    required String fileName,
    this.subtitles = const Value.absent(),
    this.totalBytes = const Value.absent(),
    required String status,
    this.problem = const Value.absent(),
    required DateTime addedAt,
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : videoId = Value(videoId),
       titleId = Value(titleId),
       quality = Value(quality),
       baseDirectory = Value(baseDirectory),
       directory = Value(directory),
       fileName = Value(fileName),
       status = Value(status),
       addedAt = Value(addedAt);
  static Insertable<DownloadRow> custom({
    Expression<String>? videoId,
    Expression<String>? titleId,
    Expression<int>? season,
    Expression<int>? episode,
    Expression<int>? episodeLast,
    Expression<bool>? finale,
    Expression<String>? titleEn,
    Expression<String>? titleAr,
    Expression<String>? posterUrl,
    Expression<String>? kind,
    Expression<int>? year,
    Expression<int>? durationMs,
    Expression<String>? quality,
    Expression<String>? baseDirectory,
    Expression<String>? directory,
    Expression<String>? fileName,
    Expression<String>? subtitles,
    Expression<int>? totalBytes,
    Expression<String>? status,
    Expression<String>? problem,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoId != null) 'video_id': videoId,
      if (titleId != null) 'title_id': titleId,
      if (season != null) 'season': season,
      if (episode != null) 'episode': episode,
      if (episodeLast != null) 'episode_last': episodeLast,
      if (finale != null) 'finale': finale,
      if (titleEn != null) 'title_en': titleEn,
      if (titleAr != null) 'title_ar': titleAr,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (kind != null) 'kind': kind,
      if (year != null) 'year': year,
      if (durationMs != null) 'duration_ms': durationMs,
      if (quality != null) 'quality': quality,
      if (baseDirectory != null) 'base_directory': baseDirectory,
      if (directory != null) 'directory': directory,
      if (fileName != null) 'file_name': fileName,
      if (subtitles != null) 'subtitles': subtitles,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (status != null) 'status': status,
      if (problem != null) 'problem': problem,
      if (addedAt != null) 'added_at': addedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsCompanion copyWith({
    Value<String>? videoId,
    Value<String>? titleId,
    Value<int?>? season,
    Value<int?>? episode,
    Value<int?>? episodeLast,
    Value<bool>? finale,
    Value<String?>? titleEn,
    Value<String?>? titleAr,
    Value<String?>? posterUrl,
    Value<String?>? kind,
    Value<int?>? year,
    Value<int?>? durationMs,
    Value<String>? quality,
    Value<String>? baseDirectory,
    Value<String>? directory,
    Value<String>? fileName,
    Value<String>? subtitles,
    Value<int?>? totalBytes,
    Value<String>? status,
    Value<String?>? problem,
    Value<DateTime>? addedAt,
    Value<DateTime?>? completedAt,
    Value<int>? rowid,
  }) {
    return DownloadsCompanion(
      videoId: videoId ?? this.videoId,
      titleId: titleId ?? this.titleId,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      episodeLast: episodeLast ?? this.episodeLast,
      finale: finale ?? this.finale,
      titleEn: titleEn ?? this.titleEn,
      titleAr: titleAr ?? this.titleAr,
      posterUrl: posterUrl ?? this.posterUrl,
      kind: kind ?? this.kind,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      quality: quality ?? this.quality,
      baseDirectory: baseDirectory ?? this.baseDirectory,
      directory: directory ?? this.directory,
      fileName: fileName ?? this.fileName,
      subtitles: subtitles ?? this.subtitles,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      problem: problem ?? this.problem,
      addedAt: addedAt ?? this.addedAt,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (titleId.present) {
      map['title_id'] = Variable<String>(titleId.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (episodeLast.present) {
      map['episode_last'] = Variable<int>(episodeLast.value);
    }
    if (finale.present) {
      map['finale'] = Variable<bool>(finale.value);
    }
    if (titleEn.present) {
      map['title_en'] = Variable<String>(titleEn.value);
    }
    if (titleAr.present) {
      map['title_ar'] = Variable<String>(titleAr.value);
    }
    if (posterUrl.present) {
      map['poster_url'] = Variable<String>(posterUrl.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (baseDirectory.present) {
      map['base_directory'] = Variable<String>(baseDirectory.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (subtitles.present) {
      map['subtitles'] = Variable<String>(subtitles.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (problem.present) {
      map['problem'] = Variable<String>(problem.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsCompanion(')
          ..write('videoId: $videoId, ')
          ..write('titleId: $titleId, ')
          ..write('season: $season, ')
          ..write('episode: $episode, ')
          ..write('episodeLast: $episodeLast, ')
          ..write('finale: $finale, ')
          ..write('titleEn: $titleEn, ')
          ..write('titleAr: $titleAr, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('kind: $kind, ')
          ..write('year: $year, ')
          ..write('durationMs: $durationMs, ')
          ..write('quality: $quality, ')
          ..write('baseDirectory: $baseDirectory, ')
          ..write('directory: $directory, ')
          ..write('fileName: $fileName, ')
          ..write('subtitles: $subtitles, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('status: $status, ')
          ..write('problem: $problem, ')
          ..write('addedAt: $addedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WatchHistoryTable watchHistory = $WatchHistoryTable(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $ContinueHiddenTable continueHidden = $ContinueHiddenTable(this);
  late final $DownloadsTable downloads = $DownloadsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    watchHistory,
    favorites,
    continueHidden,
    downloads,
  ];
}

typedef $$WatchHistoryTableCreateCompanionBuilder =
    WatchHistoryCompanion Function({
      required String videoId,
      Value<String?> seriesId,
      Value<int?> season,
      Value<int?> episode,
      required int positionMs,
      required int durationMs,
      required bool finished,
      required DateTime updatedAt,
      Value<String?> titleEn,
      Value<String?> titleAr,
      Value<String?> posterUrl,
      Value<String?> kind,
      Value<int> rowid,
    });
typedef $$WatchHistoryTableUpdateCompanionBuilder =
    WatchHistoryCompanion Function({
      Value<String> videoId,
      Value<String?> seriesId,
      Value<int?> season,
      Value<int?> episode,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<bool> finished,
      Value<DateTime> updatedAt,
      Value<String?> titleEn,
      Value<String?> titleAr,
      Value<String?> posterUrl,
      Value<String?> kind,
      Value<int> rowid,
    });

class $$WatchHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $WatchHistoryTable> {
  $$WatchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleEn => $composableBuilder(
    column: $table.titleEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleAr => $composableBuilder(
    column: $table.titleAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchHistoryTable> {
  $$WatchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get finished => $composableBuilder(
    column: $table.finished,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleEn => $composableBuilder(
    column: $table.titleEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleAr => $composableBuilder(
    column: $table.titleAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchHistoryTable> {
  $$WatchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get finished =>
      $composableBuilder(column: $table.finished, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get titleEn =>
      $composableBuilder(column: $table.titleEn, builder: (column) => column);

  GeneratedColumn<String> get titleAr =>
      $composableBuilder(column: $table.titleAr, builder: (column) => column);

  GeneratedColumn<String> get posterUrl =>
      $composableBuilder(column: $table.posterUrl, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);
}

class $$WatchHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchHistoryTable,
          WatchHistoryData,
          $$WatchHistoryTableFilterComposer,
          $$WatchHistoryTableOrderingComposer,
          $$WatchHistoryTableAnnotationComposer,
          $$WatchHistoryTableCreateCompanionBuilder,
          $$WatchHistoryTableUpdateCompanionBuilder,
          (
            WatchHistoryData,
            BaseReferences<_$AppDatabase, $WatchHistoryTable, WatchHistoryData>,
          ),
          WatchHistoryData,
          PrefetchHooks Function()
        > {
  $$WatchHistoryTableTableManager(_$AppDatabase db, $WatchHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> videoId = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> finished = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> titleEn = const Value.absent(),
                Value<String?> titleAr = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchHistoryCompanion(
                videoId: videoId,
                seriesId: seriesId,
                season: season,
                episode: episode,
                positionMs: positionMs,
                durationMs: durationMs,
                finished: finished,
                updatedAt: updatedAt,
                titleEn: titleEn,
                titleAr: titleAr,
                posterUrl: posterUrl,
                kind: kind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String videoId,
                Value<String?> seriesId = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                required int positionMs,
                required int durationMs,
                required bool finished,
                required DateTime updatedAt,
                Value<String?> titleEn = const Value.absent(),
                Value<String?> titleAr = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchHistoryCompanion.insert(
                videoId: videoId,
                seriesId: seriesId,
                season: season,
                episode: episode,
                positionMs: positionMs,
                durationMs: durationMs,
                finished: finished,
                updatedAt: updatedAt,
                titleEn: titleEn,
                titleAr: titleAr,
                posterUrl: posterUrl,
                kind: kind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchHistoryTable, WatchHistoryData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WatchHistoryTable,
                    WatchHistoryData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchHistoryTable,
      WatchHistoryData,
      $$WatchHistoryTableFilterComposer,
      $$WatchHistoryTableOrderingComposer,
      $$WatchHistoryTableAnnotationComposer,
      $$WatchHistoryTableCreateCompanionBuilder,
      $$WatchHistoryTableUpdateCompanionBuilder,
      (
        WatchHistoryData,
        BaseReferences<_$AppDatabase, $WatchHistoryTable, WatchHistoryData>,
      ),
      WatchHistoryData,
      PrefetchHooks Function()
    >;
typedef $$FavoritesTableCreateCompanionBuilder = FavoritesCompanion Function({
  required String titleId,
  Value<String?> titleEn,
  Value<String?> titleAr,
  Value<String?> posterUrl,
  Value<String?> kind,
  Value<int?> year,
  Value<String?> genreEn,
  Value<String?> genreAr,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$FavoritesTableUpdateCompanionBuilder = FavoritesCompanion Function({
  Value<String> titleId,
  Value<String?> titleEn,
  Value<String?> titleAr,
  Value<String?> posterUrl,
  Value<String?> kind,
  Value<int?> year,
  Value<String?> genreEn,
  Value<String?> genreAr,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get titleId => $composableBuilder(
    column: $table.titleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleEn => $composableBuilder(
    column: $table.titleEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleAr => $composableBuilder(
    column: $table.titleAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genreEn => $composableBuilder(
    column: $table.genreEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genreAr => $composableBuilder(
    column: $table.genreAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get titleId => $composableBuilder(
    column: $table.titleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleEn => $composableBuilder(
    column: $table.titleEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleAr => $composableBuilder(
    column: $table.titleAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genreEn => $composableBuilder(
    column: $table.genreEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genreAr => $composableBuilder(
    column: $table.genreAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get titleId =>
      $composableBuilder(column: $table.titleId, builder: (column) => column);

  GeneratedColumn<String> get titleEn =>
      $composableBuilder(column: $table.titleEn, builder: (column) => column);

  GeneratedColumn<String> get titleAr =>
      $composableBuilder(column: $table.titleAr, builder: (column) => column);

  GeneratedColumn<String> get posterUrl =>
      $composableBuilder(column: $table.posterUrl, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get genreEn =>
      $composableBuilder(column: $table.genreEn, builder: (column) => column);

  GeneratedColumn<String> get genreAr =>
      $composableBuilder(column: $table.genreAr, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoritesTable,
          FavoriteRow,
          $$FavoritesTableFilterComposer,
          $$FavoritesTableOrderingComposer,
          $$FavoritesTableAnnotationComposer,
          $$FavoritesTableCreateCompanionBuilder,
          $$FavoritesTableUpdateCompanionBuilder,
          (
            FavoriteRow,
            BaseReferences<_$AppDatabase, $FavoritesTable, FavoriteRow>,
          ),
          FavoriteRow,
          PrefetchHooks Function()
        > {
  $$FavoritesTableTableManager(_$AppDatabase db, $FavoritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> titleId = const Value.absent(),
                Value<String?> titleEn = const Value.absent(),
                Value<String?> titleAr = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> genreEn = const Value.absent(),
                Value<String?> genreAr = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                titleId: titleId,
                titleEn: titleEn,
                titleAr: titleAr,
                posterUrl: posterUrl,
                kind: kind,
                year: year,
                genreEn: genreEn,
                genreAr: genreAr,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String titleId,
                Value<String?> titleEn = const Value.absent(),
                Value<String?> titleAr = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> genreEn = const Value.absent(),
                Value<String?> genreAr = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                titleId: titleId,
                titleEn: titleEn,
                titleAr: titleAr,
                posterUrl: posterUrl,
                kind: kind,
                year: year,
                genreEn: genreEn,
                genreAr: genreAr,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FavoritesTable, FavoriteRow>(table),
                  BaseReferences<_$AppDatabase, $FavoritesTable, FavoriteRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoritesTable,
      FavoriteRow,
      $$FavoritesTableFilterComposer,
      $$FavoritesTableOrderingComposer,
      $$FavoritesTableAnnotationComposer,
      $$FavoritesTableCreateCompanionBuilder,
      $$FavoritesTableUpdateCompanionBuilder,
      (
        FavoriteRow,
        BaseReferences<_$AppDatabase, $FavoritesTable, FavoriteRow>,
      ),
      FavoriteRow,
      PrefetchHooks Function()
    >;
typedef $$ContinueHiddenTableCreateCompanionBuilder =
    ContinueHiddenCompanion Function({
      required String titleId,
      required DateTime hiddenAt,
      Value<int> rowid,
    });
typedef $$ContinueHiddenTableUpdateCompanionBuilder =
    ContinueHiddenCompanion Function({
      Value<String> titleId,
      Value<DateTime> hiddenAt,
      Value<int> rowid,
    });

class $$ContinueHiddenTableFilterComposer
    extends Composer<_$AppDatabase, $ContinueHiddenTable> {
  $$ContinueHiddenTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get titleId => $composableBuilder(
    column: $table.titleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get hiddenAt => $composableBuilder(
    column: $table.hiddenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ContinueHiddenTableOrderingComposer
    extends Composer<_$AppDatabase, $ContinueHiddenTable> {
  $$ContinueHiddenTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get titleId => $composableBuilder(
    column: $table.titleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get hiddenAt => $composableBuilder(
    column: $table.hiddenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ContinueHiddenTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContinueHiddenTable> {
  $$ContinueHiddenTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get titleId =>
      $composableBuilder(column: $table.titleId, builder: (column) => column);

  GeneratedColumn<DateTime> get hiddenAt =>
      $composableBuilder(column: $table.hiddenAt, builder: (column) => column);
}

class $$ContinueHiddenTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ContinueHiddenTable,
          HiddenContinueRow,
          $$ContinueHiddenTableFilterComposer,
          $$ContinueHiddenTableOrderingComposer,
          $$ContinueHiddenTableAnnotationComposer,
          $$ContinueHiddenTableCreateCompanionBuilder,
          $$ContinueHiddenTableUpdateCompanionBuilder,
          (
            HiddenContinueRow,
            BaseReferences<
              _$AppDatabase,
              $ContinueHiddenTable,
              HiddenContinueRow
            >,
          ),
          HiddenContinueRow,
          PrefetchHooks Function()
        > {
  $$ContinueHiddenTableTableManager(
    _$AppDatabase db,
    $ContinueHiddenTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContinueHiddenTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContinueHiddenTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContinueHiddenTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> titleId = const Value.absent(),
                Value<DateTime> hiddenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ContinueHiddenCompanion(
                titleId: titleId,
                hiddenAt: hiddenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String titleId,
                required DateTime hiddenAt,
                Value<int> rowid = const Value.absent(),
              }) => ContinueHiddenCompanion.insert(
                titleId: titleId,
                hiddenAt: hiddenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ContinueHiddenTable, HiddenContinueRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ContinueHiddenTable,
                    HiddenContinueRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ContinueHiddenTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ContinueHiddenTable,
      HiddenContinueRow,
      $$ContinueHiddenTableFilterComposer,
      $$ContinueHiddenTableOrderingComposer,
      $$ContinueHiddenTableAnnotationComposer,
      $$ContinueHiddenTableCreateCompanionBuilder,
      $$ContinueHiddenTableUpdateCompanionBuilder,
      (
        HiddenContinueRow,
        BaseReferences<_$AppDatabase, $ContinueHiddenTable, HiddenContinueRow>,
      ),
      HiddenContinueRow,
      PrefetchHooks Function()
    >;
typedef $$DownloadsTableCreateCompanionBuilder = DownloadsCompanion Function({
  required String videoId,
  required String titleId,
  Value<int?> season,
  Value<int?> episode,
  Value<int?> episodeLast,
  Value<bool> finale,
  Value<String?> titleEn,
  Value<String?> titleAr,
  Value<String?> posterUrl,
  Value<String?> kind,
  Value<int?> year,
  Value<int?> durationMs,
  required String quality,
  required String baseDirectory,
  required String directory,
  required String fileName,
  Value<String> subtitles,
  Value<int?> totalBytes,
  required String status,
  Value<String?> problem,
  required DateTime addedAt,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});
typedef $$DownloadsTableUpdateCompanionBuilder = DownloadsCompanion Function({
  Value<String> videoId,
  Value<String> titleId,
  Value<int?> season,
  Value<int?> episode,
  Value<int?> episodeLast,
  Value<bool> finale,
  Value<String?> titleEn,
  Value<String?> titleAr,
  Value<String?> posterUrl,
  Value<String?> kind,
  Value<int?> year,
  Value<int?> durationMs,
  Value<String> quality,
  Value<String> baseDirectory,
  Value<String> directory,
  Value<String> fileName,
  Value<String> subtitles,
  Value<int?> totalBytes,
  Value<String> status,
  Value<String?> problem,
  Value<DateTime> addedAt,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});

class $$DownloadsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleId => $composableBuilder(
    column: $table.titleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeLast => $composableBuilder(
    column: $table.episodeLast,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get finale => $composableBuilder(
    column: $table.finale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleEn => $composableBuilder(
    column: $table.titleEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleAr => $composableBuilder(
    column: $table.titleAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseDirectory => $composableBuilder(
    column: $table.baseDirectory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitles => $composableBuilder(
    column: $table.subtitles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get problem => $composableBuilder(
    column: $table.problem,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleId => $composableBuilder(
    column: $table.titleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeLast => $composableBuilder(
    column: $table.episodeLast,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get finale => $composableBuilder(
    column: $table.finale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleEn => $composableBuilder(
    column: $table.titleEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleAr => $composableBuilder(
    column: $table.titleAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseDirectory => $composableBuilder(
    column: $table.baseDirectory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitles => $composableBuilder(
    column: $table.subtitles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get problem => $composableBuilder(
    column: $table.problem,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);

  GeneratedColumn<String> get titleId =>
      $composableBuilder(column: $table.titleId, builder: (column) => column);

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get episodeLast => $composableBuilder(
    column: $table.episodeLast,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get finale =>
      $composableBuilder(column: $table.finale, builder: (column) => column);

  GeneratedColumn<String> get titleEn =>
      $composableBuilder(column: $table.titleEn, builder: (column) => column);

  GeneratedColumn<String> get titleAr =>
      $composableBuilder(column: $table.titleAr, builder: (column) => column);

  GeneratedColumn<String> get posterUrl =>
      $composableBuilder(column: $table.posterUrl, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<String> get baseDirectory => $composableBuilder(
    column: $table.baseDirectory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get subtitles =>
      $composableBuilder(column: $table.subtitles, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get problem =>
      $composableBuilder(column: $table.problem, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$DownloadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadsTable,
          DownloadRow,
          $$DownloadsTableFilterComposer,
          $$DownloadsTableOrderingComposer,
          $$DownloadsTableAnnotationComposer,
          $$DownloadsTableCreateCompanionBuilder,
          $$DownloadsTableUpdateCompanionBuilder,
          (
            DownloadRow,
            BaseReferences<_$AppDatabase, $DownloadsTable, DownloadRow>,
          ),
          DownloadRow,
          PrefetchHooks Function()
        > {
  $$DownloadsTableTableManager(_$AppDatabase db, $DownloadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> videoId = const Value.absent(),
                Value<String> titleId = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int?> episodeLast = const Value.absent(),
                Value<bool> finale = const Value.absent(),
                Value<String?> titleEn = const Value.absent(),
                Value<String?> titleAr = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> quality = const Value.absent(),
                Value<String> baseDirectory = const Value.absent(),
                Value<String> directory = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> subtitles = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> problem = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion(
                videoId: videoId,
                titleId: titleId,
                season: season,
                episode: episode,
                episodeLast: episodeLast,
                finale: finale,
                titleEn: titleEn,
                titleAr: titleAr,
                posterUrl: posterUrl,
                kind: kind,
                year: year,
                durationMs: durationMs,
                quality: quality,
                baseDirectory: baseDirectory,
                directory: directory,
                fileName: fileName,
                subtitles: subtitles,
                totalBytes: totalBytes,
                status: status,
                problem: problem,
                addedAt: addedAt,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String videoId,
                required String titleId,
                Value<int?> season = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int?> episodeLast = const Value.absent(),
                Value<bool> finale = const Value.absent(),
                Value<String?> titleEn = const Value.absent(),
                Value<String?> titleAr = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                required String quality,
                required String baseDirectory,
                required String directory,
                required String fileName,
                Value<String> subtitles = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                required String status,
                Value<String?> problem = const Value.absent(),
                required DateTime addedAt,
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion.insert(
                videoId: videoId,
                titleId: titleId,
                season: season,
                episode: episode,
                episodeLast: episodeLast,
                finale: finale,
                titleEn: titleEn,
                titleAr: titleAr,
                posterUrl: posterUrl,
                kind: kind,
                year: year,
                durationMs: durationMs,
                quality: quality,
                baseDirectory: baseDirectory,
                directory: directory,
                fileName: fileName,
                subtitles: subtitles,
                totalBytes: totalBytes,
                status: status,
                problem: problem,
                addedAt: addedAt,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadsTable, DownloadRow>(table),
                  BaseReferences<_$AppDatabase, $DownloadsTable, DownloadRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadsTable,
      DownloadRow,
      $$DownloadsTableFilterComposer,
      $$DownloadsTableOrderingComposer,
      $$DownloadsTableAnnotationComposer,
      $$DownloadsTableCreateCompanionBuilder,
      $$DownloadsTableUpdateCompanionBuilder,
      (
        DownloadRow,
        BaseReferences<_$AppDatabase, $DownloadsTable, DownloadRow>,
      ),
      DownloadRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WatchHistoryTableTableManager get watchHistory =>
      $$WatchHistoryTableTableManager(_db, _db.watchHistory);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
  $$ContinueHiddenTableTableManager get continueHidden =>
      $$ContinueHiddenTableTableManager(_db, _db.continueHidden);
  $$DownloadsTableTableManager get downloads =>
      $$DownloadsTableTableManager(_db, _db.downloads);
}
