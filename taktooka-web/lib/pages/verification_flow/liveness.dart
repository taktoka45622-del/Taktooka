import 'dart:math';

class MotionCheck {
  MotionCheck({bool? rightFirst})
    : rightFirst = rightFirst ?? Random.secure().nextBool();
  final bool rightFirst;
  int stage = 0, stableFrames = 0;
  bool eyesWereOpen = false, eyesClosed = false;
  int? faceId;
  DateTime? started, lastSeen;
  bool get complete => stage == 4;
  String get instruction => switch (stage) {
    0 => 'خلي وجهك داخل الإطار وانظر للكاميرا',
    1 => 'ارمش بعينيك ثم افتحهن',
    2 => rightFirst ? 'لف وجهك شوي لليمين' : 'لف وجهك شوي لليسار',
    3 => 'ارجع وانظر للكاميرا',
    _ => 'اكتمل فحص الحركة؛ اضغط التقاط',
  };
  void reset() {
    stage = 0;
    stableFrames = 0;
    eyesWereOpen = false;
    eyesClosed = false;
    faceId = null;
    started = null;
    lastSeen = null;
  }

  void observe({
    required DateTime now,
    required int count,
    required bool centered,
    int? id,
    double? leftEye,
    double? rightEye,
    double? yaw,
  }) {
    if (count != 1 || !centered) {
      stableFrames = 0;
      if (lastSeen != null && now.difference(lastSeen!).inMilliseconds > 800)
        reset();
      return;
    }
    if (faceId != null && id != null && faceId != id) reset();
    if (started != null && now.difference(started!).inSeconds > 45) reset();
    faceId = id;
    lastSeen = now;
    started ??= now;
    final straight = yaw != null && yaw.abs() < 12;
    final open =
        leftEye != null && rightEye != null && leftEye > .65 && rightEye > .65;
    final closed =
        leftEye != null && rightEye != null && leftEye < .3 && rightEye < .3;
    if (stage == 0) {
      stableFrames = straight && open ? stableFrames + 1 : 0;
      if (stableFrames >= 3) {
        stage = 1;
        eyesWereOpen = true;
        stableFrames = 0;
      }
    } else if (stage == 1 && straight) {
      if (eyesWereOpen && closed) eyesClosed = true;
      if (eyesClosed && open) stage = 2;
    } else if (stage == 2 && yaw != null) {
      final turned = rightFirst ? yaw > 22 : yaw < -22;
      stableFrames = turned ? stableFrames + 1 : 0;
      if (stableFrames >= 2) {
        stage = 3;
        stableFrames = 0;
      }
    } else if (stage == 3) {
      stableFrames = straight && open ? stableFrames + 1 : 0;
      if (stableFrames >= 3) stage = 4;
    }
  }

  Map<String, dynamic> report() => {
    'method': 'device_motion_v1',
    'blink': complete,
    'turn': complete,
    'single_face': complete,
    'direction': rightFirst ? 'right' : 'left',
    'checked_at': DateTime.now().toUtc().toIso8601String(),
    'assurance': 'device_assisted_admin_review',
  };
}
