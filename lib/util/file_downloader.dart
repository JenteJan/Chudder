import 'package:universal_html/html.dart' as html;

Future<void> downloadFile(String url) async {
  try {
    html.AnchorElement anchorElement = html.AnchorElement(href: url);
    // Empty: the browser takes the server's file name. The URL itself
    // carries the account token and doesn't belong in a file name or the
    // download list.
    anchorElement.download = '';
    anchorElement.click();
  } catch (e) {
    print('Download error: $e');
  }
}
