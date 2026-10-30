import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/verification_flow/document_edges.dart';
import 'package:taktooka/pages/verification_flow/liveness.dart';

class CaptureResult {
  final XFile file;
  final Map<String, dynamic> checks;
  const CaptureResult(this.file, this.checks);
}

Future<bool> validPersonalPhoto(XFile file) async {
  final detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  );
  try {
    final faces = await detector.processImage(
      InputImage.fromFilePath(file.path),
    );
    if (faces.length != 1) return false;
    final rect = faces.single.boundingBox;
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) return false;
    final photo = img.bakeOrientation(decoded);
    final fraction = rect.width * rect.height / (photo.width * photo.height);
    return rect.width >= 80 &&
        rect.height >= 80 &&
        fraction >= .08 &&
        fraction <= .9;
  } finally {
    await detector.close();
  }
}

class CapturePage extends StatefulWidget {
  final String title;
  final bool face;
  final bool directCapture;
  const CapturePage({
    super.key,
    required this.title,
    this.face = false,
    this.directCapture = false,
  });
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  CameraController? controller;
  late final detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  final check = MotionCheck();
  bool loading = true,
      processing = false,
      capturing = false,
      paused = false,
      closing = false;
  String? error;
  DateTime lastFrame = DateTime(2000);
  int generation = 0;
  Future<void>? analysisTask;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    openCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      generation++;
      final old = controller;
      controller = null;
      check.reset();
      if (old != null) unawaited(old.dispose());
      if (mounted)
        setState(() {
          paused = true;
          loading = false;
        });
    }
  }

  Future<void> openCamera() async {
    final revision = ++generation;
    setState(() {
      loading = true;
      error = null;
      paused = false;
    });
    try {
      final cameras = await availableCameras();
      final lens = widget.face
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final matching = cameras.where((c) => c.lensDirection == lens);
      if (matching.isEmpty) throw StateError('CAMERA_UNAVAILABLE');
      final next = CameraController(
        matching.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await next.initialize();
      if (!mounted || revision != generation) {
        await next.dispose();
        return;
      }
      controller = next;
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (widget.face)
        await next.startImageStream((frame) {
          if (processing ||
              capturing ||
              closing ||
              DateTime.now().difference(lastFrame).inMilliseconds < 100)
            return;
          lastFrame = DateTime.now();
          analysisTask = analyze(frame, next);
        });
    } catch (e) {
      if (mounted && revision == generation)
        error = e is CameraException && e.code.contains('Denied')
            ? 'اسمح باستخدام الكاميرا من إعدادات الجهاز'
            : 'تعذّر فتح الكاميرا؛ أعد المحاولة';
    } finally {
      if (mounted && revision == generation) setState(() => loading = false);
    }
  }

  InputImage? inputImage(CameraImage frame, CameraController c) {
    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    if (frame.planes.length != 1 || format == null) return null;
    final orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    var rotation = c.description.sensorOrientation;
    if (Platform.isAndroid) {
      final comp = orientations[c.value.deviceOrientation] ?? 0;
      rotation = c.description.lensDirection == CameraLensDirection.front
          ? (rotation + comp) % 360
          : (rotation - comp + 360) % 360;
    }
    final rot = InputImageRotationValue.fromRawValue(rotation);
    if (rot == null) return null;
    return InputImage.fromBytes(
      bytes: frame.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rot,
        format: format,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> analyze(CameraImage frame, CameraController c) async {
    processing = true;
    try {
      final input = inputImage(frame, c);
      if (input == null) {
        if (mounted)
          setState(
            () => error = 'صيغة الكاميرا غير مدعومة للفحص؛ جرّب جهازًا آخر',
          );
        return;
      }
      final faces = await detector.processImage(input);
      if (!mounted || closing || controller != c) return;
      final f = faces.length == 1 ? faces.single : null;
      final rotation = input.metadata!.rotation;
      final swapped =
          rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final w = (swapped ? frame.height : frame.width).toDouble(),
          h = (swapped ? frame.width : frame.height).toDouble();
      final rect = f?.boundingBox;
      final centered =
          rect != null &&
          rect.width > w * .23 &&
          rect.width < w * .85 &&
          (rect.center.dx - w / 2).abs() < w * .2 &&
          (rect.center.dy - h / 2).abs() < h * .23;
      check.observe(
        now: DateTime.now(),
        count: faces.length,
        centered: centered,
        id: f?.trackingId,
        leftEye: f?.leftEyeOpenProbability,
        rightEye: f?.rightEyeOpenProbability,
        yaw: f?.headEulerAngleY,
      );
      setState(
        () => error = faces.length > 1 ? 'خلي وجهك وحده داخل الكاميرا' : null,
      );
    } catch (_) {
      if (mounted && !closing)
        setState(() => error = 'تعذّر فحص الوجه؛ اضغط إعادة الفحص');
    } finally {
      processing = false;
    }
  }

  Future<void> capture() async {
    final c = controller;
    if (c == null || capturing || (widget.face && !check.complete)) return;
    setState(() => capturing = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await analysisTask;
      final file = await c.takePicture();
      if (!mounted) return;
      CaptureResult? result;
      if (widget.directCapture && !widget.face) {
        result = CaptureResult(file, {});
      } else if (widget.face) {
        if (!await validPersonalPhoto(file)) throw StateError('FACE_REQUIRED');
        result = CaptureResult(file, check.report());
      } else {
        final bytes = await file.readAsBytes();
        final crop = await compute(cropDocument, bytes);
        if (!mounted) return;
        final adjusted = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
            builder: (_) =>
                DocumentReview(bytes: crop.jpeg, detected: crop.detected),
          ),
        );
        if (adjusted != null) {
          final path = '${file.path}.card.jpg';
          await File(path).writeAsBytes(adjusted);
          result = CaptureResult(XFile(path), {
            'edge_detected': crop.detected,
            'user_confirmed': true,
          });
        }
      }
      if (!mounted) return;
      if (result != null) {
        closing = true;
        Navigator.of(context).pop(result);
      } else if (widget.face)
        check.reset();
    } catch (e) {
      if (mounted)
        setState(
          () => error = e.toString().contains('FACE_REQUIRED')
              ? 'الصورة لازم بيها وجه واحد واضح؛ أعد الفحص'
              : 'تعذّر التقاط الصورة، أعد المحاولة',
        );
    } finally {
      if (mounted && !closing) {
        setState(() => capturing = false);
        if (widget.face && controller == c && !c.value.isStreamingImages) {
          check.reset();
          await c.startImageStream((frame) {
            if (!processing &&
                !capturing &&
                !closing &&
                DateTime.now().difference(lastFrame).inMilliseconds >= 100) {
              lastFrame = DateTime.now();
              analysisTask = analyze(frame, c);
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    closing = true;
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    final c = controller;
    controller = null;
    unawaited(c?.dispose() ?? Future<void>.value());
    unawaited(
      (analysisTask ?? Future<void>.value()).whenComplete(
        () => detector.close(),
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: AppText(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppText(
            widget.face
                ? check.instruction
                : 'حط البطاقة أفقياً داخل الإطار، بإضاءة واضحة وبدون انعكاس',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: widget.face ? 3 / 4 : 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (c != null && c.value.isInitialized)
                    LayoutBuilder(
                      builder: (_, box) {
                        final aspect = 1 / c.value.aspectRatio;
                        final width = math.max(
                          box.maxWidth,
                          box.maxHeight * aspect,
                        );
                        return ClipRect(
                          child: OverflowBox(
                            maxWidth: double.infinity,
                            maxHeight: double.infinity,
                            child: SizedBox(
                              width: width,
                              height: width / aspect,
                              child: CameraPreview(c),
                            ),
                          ),
                        );
                      },
                    ),
                  if (loading) const Center(child: CircularProgressIndicator()),
                  if (!loading && !paused)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.face ? 40 : 24,
                        vertical: widget.face ? 35 : 18,
                      ),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: widget.face && check.complete
                                  ? Colors.green
                                  : Colors.white,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(
                              widget.face ? 160 : 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.face) ...[
            LinearProgressIndicator(value: check.stage / 4),
            const SizedBox(height: 12),
            const AppText(
              'فحص حركة الوجه يساعد الإدارة على المراجعة؛ ما يُعتبر بصمة قزحية أو إثبات هوية نهائي.',
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppText(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (paused || c == null && !loading)
            FilledButton.icon(
              onPressed: openCamera,
              icon: const Icon(Icons.camera_alt),
              label: const AppText('فتح الكاميرا'),
            ),
          if (widget.face && !paused)
            TextButton(
              onPressed: capturing ? null : () => setState(check.reset),
              child: const AppText('إعادة الفحص'),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed:
                loading ||
                    paused ||
                    capturing ||
                    c == null ||
                    widget.face && !check.complete
                ? null
                : capture,
            icon: const Icon(Icons.camera_alt),
            label: AppText(capturing ? 'جاري معالجة الصورة…' : 'التقاط'),
          ),
        ],
      ),
    );
  }
}

class DocumentReview extends StatefulWidget {
  final Uint8List bytes;
  final bool detected;
  const DocumentReview({
    super.key,
    required this.bytes,
    required this.detected,
  });
  @override
  State<DocumentReview> createState() => _DocumentReviewState();
}

class _DocumentReviewState extends State<DocumentReview> {
  double left = 0, top = 0, right = 1, bottom = 1;
  bool saving = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('معاينة البطاقة')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppText(
          widget.detected
              ? 'تم تحديد الحواف؛ تأكد من وضوح البطاقة بالكامل'
              : 'لم تتضح الحواف تلقائيًا؛ عدّل حدود القص أو أعد الالتقاط',
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(widget.bytes, fit: BoxFit.fill),
              LayoutBuilder(
                builder: (_, b) => Stack(
                  children: [
                    Positioned(
                      left: b.maxWidth * left,
                      top: b.maxHeight * top,
                      width: b.maxWidth * (right - left),
                      height: b.maxHeight * (bottom - top),
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const AppText('حدود القص الأفقية'),
        RangeSlider(
          values: RangeValues(left, right),
          min: 0,
          max: 1,
          onChanged: saving
              ? null
              : (v) {
                  if (v.end - v.start > .25)
                    setState(() {
                      left = v.start;
                      right = v.end;
                    });
                },
        ),
        const AppText('حدود القص العمودية'),
        RangeSlider(
          values: RangeValues(top, bottom),
          min: 0,
          max: 1,
          onChanged: saving
              ? null
              : (v) {
                  if (v.end - v.start > .25)
                    setState(() {
                      top = v.start;
                      bottom = v.end;
                    });
                },
        ),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  setState(() => saving = true);
                  try {
                    final result = await compute(manualDocumentCrop, {
                      'bytes': widget.bytes,
                      'left': left,
                      'top': top,
                      'right': right,
                      'bottom': bottom,
                    });
                    if (context.mounted) Navigator.pop(context, result);
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          child: const AppText('الصورة واضحة، اعتماد'),
        ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const AppText('إعادة الالتقاط'),
        ),
      ],
    ),
  );
}
