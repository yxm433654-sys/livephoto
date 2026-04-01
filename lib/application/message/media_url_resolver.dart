class MediaUrlResolver {
  const MediaUrlResolver(this.apiBaseUrl);

  final String apiBaseUrl;

  String resolve(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }
    final base = Uri.parse(apiBaseUrl);
    final path = url.startsWith('/') ? url : '/$url';
    return base.replace(path: path, query: null, fragment: null).toString();
  }
}
