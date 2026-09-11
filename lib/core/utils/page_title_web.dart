import 'package:web/web.dart' as web;

/// Web implementation of [setPageTitle] — sets the browser tab's title.
void setPageTitle(String title) {
  web.document.title = title;
}
