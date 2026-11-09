import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:carservice_business/app/theme/app_theme.dart';

/// Гарын үсгийн цэгүүдийг цагаан дэвсгэртэй PNG болгон экспортлоно.
/// Зураас байхгүй бол `null`.
Future<Uint8List?> exportSignaturePng(
  List<List<Offset>> strokes,
  Size size, {
  double pixelRatio = 2,
}) async {
  if (strokes.every((s) => s.isEmpty)) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  SignaturePainter(strokes, color: Colors.black).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (size.width * pixelRatio).round(),
    (size.height * pixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data?.buffer.asUint8List();
}

/// Pointer down-д шууд gesture arena-г ялдаг recognizer.
class _EagerRecognizer extends OneSequenceGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'eager';

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }
}

class SignaturePainter extends CustomPainter {
  SignaturePainter(this.strokes, {required this.color});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter old) => true;
}

/// Хуруугаар зурах талбар. Зураасыг [strokes]-д хуримтлуулж, өөрчлөлт
/// бүрт [onChanged] дуудна.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.strokes,
    required this.onChanged,
    this.height = 180,
  });

  final List<List<Offset>> strokes;
  final VoidCallback onChanged;
  final double height;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final _boxKey = GlobalKey();

  /// Экспортод ашиглах одоогийн хэмжээ.
  Size get size => (_boxKey.currentContext?.size) ?? Size.zero;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
      child: Container(
        key: _boxKey,
        height: widget.height,
        width: double.infinity,
        color: Colors.white,
        // Eager recognizer: пад нь gesture arena-д шууд ялж, зурах үед
        // хүрээлсэн scroll view гүйлгэгдэхгүй. Цэгүүдийг Listener-ээр авна.
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _EagerRecognizer:
                GestureRecognizerFactoryWithHandlers<_EagerRecognizer>(
                  _EagerRecognizer.new,
                  (_) {},
                ),
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              widget.strokes.add([e.localPosition]);
              widget.onChanged();
              setState(() {});
            },
            onPointerMove: (e) {
              if (widget.strokes.isEmpty) return;
              widget.strokes.last.add(e.localPosition);
              widget.onChanged();
              setState(() {});
            },
            child: CustomPaint(
              painter: SignaturePainter(widget.strokes, color: Colors.black),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}
