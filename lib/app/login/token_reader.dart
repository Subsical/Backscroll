import 'dart:convert';

const discordLoginUrl = 'https://discord.com/login';

// Discord deletes window.localStorage once its client boots, but a fresh
// iframe from the same origin still hands out the real storage object.
const tokenScript =
    '(function(){try{'
    "if(/^\\/(login|register)/.test(location.pathname))return '';"
    "var f=document.createElement('iframe');f.style.display='none';"
    'document.documentElement.appendChild(f);'
    "var t=f.contentWindow.localStorage.getItem('token');f.remove();"
    "return t?JSON.parse(t):'';"
    "}catch(e){return '';}})()";

String? parseTokenResult(Object? result) {
  if (result == null) return null;
  var value = '$result'.trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    try {
      value = jsonDecode(value) as String;
    } on FormatException {
      return null;
    }
  }
  if (value.isEmpty || value == 'null' || value.contains(RegExp(r'\s'))) {
    return null;
  }
  return value;
}

bool allowedInLoginView(Uri? uri) {
  if (uri == null) return false;
  if (uri.scheme == 'about' || uri.scheme == 'blob' || uri.scheme == 'data') {
    return true;
  }
  return uri.scheme == 'https';
}
