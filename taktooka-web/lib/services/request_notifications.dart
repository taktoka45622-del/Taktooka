/// Shared by foreground and background handlers. Food requests use the same
/// bounded ringtone as ride offers, with separate IDs for each request round.
bool isFoodRequest(Map<String, dynamic> notice) =>
    notice['kind'] == 'food' &&
    const ['restaurant', 'courier'].contains(notice['request_type']);
bool isIncomingRequest(Map<String, dynamic> notice) =>
    notice['kind'] == 'offer' || isFoodRequest(notice);
