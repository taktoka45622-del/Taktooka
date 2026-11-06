bool isFoodRequest(Map<String, dynamic> notice) =>
    notice['kind'] == 'food' &&
    const ['restaurant', 'courier'].contains(notice['request_type']);
bool isIncomingRequest(Map<String, dynamic> notice) =>
    notice['kind'] == 'offer' || isFoodRequest(notice);
