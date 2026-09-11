import 'page_title_stub.dart'
    if (dart.library.js_interop) 'page_title_web.dart'
    as impl;

/// Sets the browser tab's title to "e-dictation: [suffix]" — e.g.
/// "Teacher mode" while signed in as a teacher, or a student's own name
/// once they've entered it on a share-link screen (dictation, cards, or
/// quiz practice). A no-op on non-web platforms.
void setPageTitle(String suffix) =>
    impl.setPageTitle('e-dictation: $suffix');
