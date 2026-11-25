import 'package:flutter/material.dart';

import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import 'package:chudder/screens/shared/media/external_urls.dart' as ext;

/// Tags that never render from server text. Overviews are written by anyone
/// who can edit metadata (or come from a scraped NFO), so they are treated as
/// untrusted: frames and embeds would load (and on web, run) another page
/// inside Chudder, and media tags would start fetching from arbitrary hosts.
const _blockedTags = {
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'script',
  'noscript',
  'style',
  'link',
  'meta',
  'base',
  'video',
  'audio',
  'source',
  'track',
  'svg',
  'math',
  'form',
  'input',
  'button',
  'select',
  'textarea',
};

/// The HTML factory without web views or JavaScript. The package enables both
/// by default, which turned an `<iframe src="javascript:…">` in an overview
/// into script running in the app.
class _SafeHtmlFactory extends WidgetFactory {
  @override
  bool get webView => false;

  @override
  bool get webViewJs => false;
}

/// [HtmlWidget] for server-supplied text such as overviews: formatting tags
/// render, frames, scripts, forms and media are dropped, and a tapped link
/// opens only when it is an http(s) address.
class SafeHtml extends StatelessWidget {
  final String html;
  final TextStyle? textStyle;

  const SafeHtml(this.html, {this.textStyle, super.key});

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      html,
      textStyle: textStyle,
      factoryBuilder: _SafeHtmlFactory.new,
      customWidgetBuilder: (element) =>
          _blockedTags.contains(element.localName?.toLowerCase()) ? const SizedBox.shrink() : null,
      onTapUrl: (url) async {
        // Returning true marks the tap as handled, so the package never
        // launches anything itself; ext.launchUrl opens web links only.
        await ext.launchUrl(context, url);
        return true;
      },
    );
  }
}
