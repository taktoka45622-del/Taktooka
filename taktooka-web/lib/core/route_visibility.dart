bool showTripRoute({required bool captainView, required String? status}) =>
    captainView ||
    const {'accepted', 'arrived', 'in_progress', 'completed'}.contains(status);
