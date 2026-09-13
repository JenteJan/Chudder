import 'package:http/http.dart' as http;

/// The browser owns connection reuse on the web.
http.Client createPooledHttpClient() => http.Client();
