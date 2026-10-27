import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/services/backend.dart';

class PhoneAuthFailure implements Exception {
  final Map<String, dynamic> data;
  PhoneAuthFailure(this.data);
}

Future<Map<String, dynamic>> phoneAuth(
  Backend b,
  Map<String, dynamic> body,
) async {
  try {
    final response = await b.db.functions
        .invoke('taktooka-phone-auth', body: body)
        .timeout(const Duration(seconds: 20));
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw PhoneAuthFailure(data);
    return data;
  } on FunctionException catch (e) {
    throw PhoneAuthFailure(
      e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : {'error': 'LOGIN_UNAVAILABLE'},
    );
  }
}
