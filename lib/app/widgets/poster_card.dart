import 'package:material_ui/material_ui.dart';

import '../../core/platform/platform_info.dart';
import '../../data/models/media_item.dart';
import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';
import 'media_image.dart';
import 'media_text.dart';

/// Height of the two text lines under a poster.
const double posterTextHeight = 44;

/// A 2:3 poster with the title (one line) and "year · genre" under it
/// (DESIGN.md §5). It is a single focusable button; the focus ring is
/// `bulb` so keyboard users on desktop can see where they are.
class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  /// The card's height for a given width.
  static double heightFor(double width) => width * 1.5 + posterTextHeight;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
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
        onTap: widget.onTap,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f && isTv) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.35,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
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
                      ? Border.all(color: MarqueeColors.bulb, width: 2)
                      : null,
                ),
                child: MediaImage(
                  url: isTv
                      ? (item.hdPosterUrl ?? item.posterUrl)
                      : item.posterUrl,
                  borderRadius: _radius,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.label,
            ),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
