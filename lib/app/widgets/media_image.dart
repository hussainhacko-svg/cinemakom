import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../theme/marquee_colors.dart';

/// Whether [MediaImage] loads from the network. Widget tests turn it off.
final networkImagesProvider = Provider<bool>((ref) => true);

/// A poster, cover or photo from the image host, with the shared request
/// headers, decoded at its displayed size (DESIGN.md §6) and cached on disk.
///
/// While loading, or when there is no image, it is a plain `booth` block:
/// no shimmer, no fade (no opacity animation over images).
class MediaImage extends ConsumerWidget {
  const MediaImage({
    super.key,
    required this.url,
    this.borderRadius = BorderRadius.zero,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String? url;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = this.url;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.booth,
        borderRadius: borderRadius,
      ),
    );
    if (url == null || !ref.watch(networkImagesProvider)) {
      return SizedBox.expand(child: placeholder);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Decode at the size on screen, never at the source size: a detail
        // poster can be 2000×3000.
        final width = box.hasBoundedWidth ? (box.maxWidth * dpr).round() : null;
        final image = CachedNetworkImage(
          imageUrl: url,
          httpHeaders: ApiClient.defaultHeaders,
          memCacheWidth: width,
          fit: fit,
          alignment: alignment,
          width: box.hasBoundedWidth ? box.maxWidth : null,
          height: box.hasBoundedHeight ? box.maxHeight : null,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => placeholder,
        );
        return borderRadius == BorderRadius.zero
            ? image
            : ClipRRect(borderRadius: borderRadius, child: image);
      },
    );
  }
}
