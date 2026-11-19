import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in Safari or the matching app. Returns false when iOS
/// refused to open it.
Future<bool> openExternal(String url) async {
  final uri = Uri.parse(url);
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Apple Maps search URL for [address]. Empty input is not a URL.
Uri? appleMapsUri(String address) {
  final text = address.trim();
  if (text.isEmpty) return null;
  return Uri.https('maps.apple.com', '/', {'q': text});
}

/// Opens [address] in Apple Maps. Returns false when it could not open.
Future<bool> openAppleMaps(String address) async {
  final uri = appleMapsUri(address);
  if (uri == null) return false;
  return openExternal(uri.toString());
}
