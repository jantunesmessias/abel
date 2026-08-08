import 'package:web/web.dart' as web;

void replaceCurrentLocation(Uri uri) {
  final browserHistory = web.window.history;
  browserHistory.replaceState(browserHistory.state, '', uri.toString());
}
