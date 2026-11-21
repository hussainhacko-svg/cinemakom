import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/widgets/media_image.dart' show networkImagesProvider;
import '../../../core/network/api_client.dart';
import '../../../core/storage/image_cache.dart';
import '../../../data/models/playback_models.dart';

/// A sprite sheet with the shared headers, through the image cache. The
/// player prefetches with the same provider, so the frame shows at once.
ImageProvider seekSheetImage(String url) => CachedNetworkImageProvider(
  url,
  headers: ApiClient.defaultHeaders,
  cacheManager: appImageCache,
);

/// One seek-preview frame: its cell of the sprite sheet, drawn with
/// `drawImageRect` (PLAYER.md §7.8), stretched to [width] × [height]. A
/// `booth` box while the sheet loads, or when it can't.
class SeekPreviewFrame extends ConsumerStatefulWidget {
  const SeekPreviewFrame({
    super.key,
    required this.frame,
    this.aspectRatio,
    this.height = minHeight,
  });

  final SeekFrame frame;
  final double height;

  /// The video's shape. The server squeezes every frame into a 16:9 cell,
  /// so drawing the cell at the video's shape undoes it.
  final double? aspectRatio;

  static const minHeight = 90.0;
  static const maxHeight = 150.0;
  static const _cellRatio = 16 / 9;

  /// 90 dp on a phone, growing with the window to 150 dp on a big monitor.
  static double heightFor(double screenWidth) =>
      (screenWidth * 0.09).clamp(minHeight, maxHeight).roundToDouble();

  /// Wide enough for the video's shape, within reason.
  double get width =>
      height * (aspectRatio ?? _cellRatio).clamp(1.2, 2.5).toDouble();
  static const radius = Radius.circular(6);

  @override
  ConsumerState<SeekPreviewFrame> createState() => _SeekPreviewFrameState();
}

class _SeekPreviewFrameState extends ConsumerState<SeekPreviewFrame> {
  ImageStream? _stream;
  ImageInfo? _sheet;
  String? _url;
  late final _listener = ImageStreamListener((info, _) {
    if (!mounted) return info.dispose();
    setState(() {
      _sheet?.dispose();
      _sheet = info;
    });
  }, onError: (_, _) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(SeekPreviewFrame old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  void _resolve() {
    final url = widget.frame.url;
    if (url == _url || !ref.read(networkImagesProvider)) return;
    _url = url;
    _stream?.removeListener(_listener);
    _sheet?.dispose();
    _sheet = null;
    _stream = seekSheetImage(
      url,
    ).resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _sheet?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: Size(widget.width, widget.height),
    child: CustomPaint(
      painter: _FramePainter(
        _sheet?.image,
        widget.frame,
        context.palette.booth,
      ),
    ),
  );
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.sheet, this.frame, this.placeholder);

  final ui.Image? sheet;
  final SeekFrame frame;
  final Color placeholder;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(dst, SeekPreviewFrame.radius);
    final sheet = this.sheet;
    if (sheet == null) {
      canvas.drawRRect(shape, Paint()..color = placeholder);
      return;
    }
    final src = Rect.fromLTWH(
      frame.x.toDouble(),
      frame.y.toDouble(),
      frame.width.toDouble(),
      frame.height.toDouble(),
    );
    canvas
      ..save()
      ..clipRRect(shape)
      ..drawImageRect(
        sheet,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.high,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.sheet != sheet ||
      old.frame != frame ||
      old.placeholder != placeholder;
}
