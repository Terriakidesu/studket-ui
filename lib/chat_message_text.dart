import 'dart:convert';

String formatChatMessagePreview(String messageText) {
  final String trimmed = messageText.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final Map<String, dynamic>? inquiry = _parsePrefixedJson(
    trimmed,
    '[studket_inquiry]',
  );
  if (inquiry != null) {
    final String name = _readName(inquiry);
    return name.isEmpty ? 'A new inquiry' : 'A new inquiry about $name';
  }

  final Map<String, dynamic>? qrConfirmation = _parsePrefixedJson(
    trimmed,
    '[studket_qr_confirmation_started]',
  );
  if (qrConfirmation != null) {
    final String name = _readNestedProductName(qrConfirmation);
    return name.isEmpty ? 'QR confirmation started' : 'QR confirmation: $name';
  }

  final Map<String, dynamic>? completed = _parsePrefixedJson(
    trimmed,
    '[studket_transaction_completed]',
  );
  if (completed != null) {
    final String name = _readNestedProductName(completed);
    return name.isEmpty
        ? 'Transaction completed'
        : 'Transaction completed: $name';
  }

  final Map<String, dynamic>? accepted = _parsePrefixedJson(
    trimmed,
    '[studket_offer_accepted]',
  );
  if (accepted != null) {
    final String name = _readName(accepted);
    return name.isEmpty ? 'Inquiry accepted' : 'Inquiry accepted: $name';
  }

  final Map<String, dynamic>? rejected = _parsePrefixedJson(
    trimmed,
    '[studket_offer_rejected]',
  );
  if (rejected != null) {
    final String name = _readName(rejected);
    return name.isEmpty ? 'Inquiry rejected' : 'Inquiry rejected: $name';
  }

  return trimmed;
}

Map<String, dynamic>? _parsePrefixedJson(String messageText, String prefix) {
  if (!messageText.startsWith(prefix)) {
    return null;
  }
  final String rawJson = messageText.substring(prefix.length);
  try {
    final dynamic decoded = jsonDecode(rawJson);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _readName(Map<String, dynamic> json) {
  return (json['name'] ?? json['title'] ?? '').toString().trim();
}

String _readNestedProductName(Map<String, dynamic> json) {
  final dynamic product = json['product'];
  if (product is Map<String, dynamic>) {
    return _readName(product);
  }
  return '';
}
