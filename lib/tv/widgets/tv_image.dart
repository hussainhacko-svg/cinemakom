import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/media_image.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/image_cache.dart';
import '../theme/tv_space.dart';

/// When scrolling has stopped, so cards on screen can swap their thumbnail
/// for the original (docs/TV.md §9.1, Loading). Fed by [onScroll] at the
/// app root.
abstract final class TvArtwork {
  static final settled = ValueNotifier<bool>(true);
  static Timer? _timer;

  /// How long scrolling must have stopped.
  static const settle = Duration(milliseconds: 250);

  static bool onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _timer?.cancel();
      settled.value = false;
    } else if (n is ScrollEndNotification) {
      _timer?.cancel();
      _timer = Timer(settle, () => settled.value = true);
    }
    return false;
  }

  /// The image cache for TV artwork, sized from the measured pixel ratio
  /// (§9.1, Memory): 150 MB at 2×, 250 MB at 4×.
  static void sizeCache(double devicePixelRatio) {
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        (devicePixelRatio >= 3 ? 250 : 150) << 20;
  }
}

/// A TV poster, cover or photo, sharp on a 4K panel (docs/TV.md §9.1):
/// - [url] (the 293 px thumbnail) shows at once; once scrolling has stopped
///   [hdUrl] (the original upload) takes its place, with no fade and no
///   layout shift;
/// - decoded at the size it reaches on screen in real pixels: × the
///   measured pixel ratio, × 1.08 when it's a card that grows on focus
///   ([grows]), never more;
/// - scaled with `FilterQuality.medium`, so a large original and the grow
///   stay smooth.
/// A plain `booth` block while loading or without an image (no shimmer).
class TvImage extends ConsumerStatefulWidget {
  const TvImage({
    super.key,
    required this.url,
    this.hdUrl,
    this.radius = 0,
    this.grows = false,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String? url;
  final String? hdUrl;
  final double radius;
  final bool grows;
  final BoxFit fit;
  final Alignment alignment;

  @override
  ConsumerState<TvImage> createState() => _TvImageState();
}

class _TvImageState extends ConsumerState<TvImage> {
  bool _hd = TvArtwork.settled.value;

  @override
  void initState() {
    super.initState();
    if (!_hd) TvArtwork.settled.addListener(_settled);
  }

  void _settled() {
    if (!TvArtwork.settled.value || !mounted) return;
    TvArtwork.settled.removeListener(_settled);
    setState(() => _hd = true);
  }

  @override
  void dispose() {
    TvArtwork.settled.removeListener(_settled);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.booth,
        borderRadius: radius,
      ),
    );
    final thumb = widget.url ?? widget.hdUrl;
    if (thumb == null || !ref.watch(networkImagesProvider)) {
      return SizedBox.expand(child: placeholder);
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.hasBoundedWidth
            ? (box.maxWidth *
                      ratio *
                      (widget.grows ? TvFocusStyle.cardScale : 1))
                  .ceil()
            : null;
        Widget image(String url, Widget Function() waiting) =>
            CachedNetworkImage(
              imageUrl: url,
              httpHeaders: ApiClient.defaultHeaders,
              cacheManager: appImageCache,
              memCacheWidth: width,
              fit: widget.fit,
              alignment: widget.alignment,
              filterQuality: FilterQuality.medium,
              width: box.hasBoundedWidth ? box.maxWidth : null,
              height: box.hasBoundedHeight ? box.maxHeight : null,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => waiting(),
              errorWidget: (_, _, _) => waiting(),
            );
        final low = image(thumb, () => placeholder);
        final hd = widget.hdUrl;
        final shown = _hd && hd != null && hd != thumb
            ? image(hd, () => low)
            : low;
        return ClipRRect(borderRadius: radius, child: shown);
      },
    );
  }
}
