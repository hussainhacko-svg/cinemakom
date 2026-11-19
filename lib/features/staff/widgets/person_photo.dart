import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_image.dart';

/// A person's round photo (`booth` fill, `velvet` border), or their
/// initials when there is none.
class PersonPhoto extends StatelessWidget {
  const PersonPhoto({
    super.key,
    required this.name,
    required this.imageUrl,
    this.size = 64,
  });

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MarqueeColors.booth,
        border: Border.fromBorderSide(BorderSide(color: MarqueeColors.velvet)),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: imageUrl == null
          ? Text(
              initials,
              style: text.label.copyWith(
                color: MarqueeColors.dust,
                fontSize: size * 0.22,
              ),
            )
          : MediaImage(url: imageUrl),
    );
  }
}
