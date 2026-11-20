import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/models/media_item.dart';
import 'tv_focus.dart';

/// Height of the two text lines under a TV poster.
const double tvPosterTextHeight = 46;

/// A 2:3 TV poster card: loads the full-resolution `hdPosterUrl`, decoded at
/// 2× sharpness for 4K TV upscaling, with a crisp 2 px `bulb` focus ring.
class TvPosterCard extends StatefulWidget {
  const TvPosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool autofocus;

  static double heightFor(double width) => width * 1.5 + tvPosterTextHeight;

  @override
  State<TvPosterCard> createState() => _TvPosterCardState();
}

class _TvPosterCardState extends State<TvPosterCard> {
  bool _focused = false;
  static const _radius = BorderRadius.all(MarqueeRadius.poster);

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final item = widget.item;
    final title = context.titleOf(item);
    final meta = context.cardMeta(item);
    return Semantics(
      button: true,
      label: meta.isEmpty ? title : '$title, $meta',
      excludeSemantics: true,
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) tvEnsureVisible(context, alignment: 0.35);
        },
        borderRadius: _radius,
        focusColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: _radius,
                  border: _focused
                      ? Border.all(color: MarqueeColors.bulb, width: 2.5)
                      : null,
                ),
                child: MediaImage(
                  url: item.hdPosterUrl ?? item.posterUrl,
                  borderRadius: _radius,
                  decodeScale: 2.0,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _focused
                  ? text.label.copyWith(color: MarqueeColors.bulb)
                  : text.label,
            ),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.caption.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
