import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/catalog_providers.dart';
import '../../data/models/media_details.dart';
import '../../data/repositories/media_repository.dart';

/// A person's page (`staff/actorID`); `null` when the server has none. The
/// role comes back in the UI language.
final staffProvider = FutureProvider.autoDispose.family<StaffPage?, String>(
  (ref, id) => ref
      .read(mediaRepositoryProvider)
      .staff(id, ref.watch(apiLanguageProvider)),
);
