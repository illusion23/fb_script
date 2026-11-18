import 'package:flutter/material.dart';

/// Detects whether [text] starts with or predominantly uses RTL characters
/// (Arabic, Hebrew, Persian, Urdu) so multilingual posts render naturally.
TextDirection detectTextDirection(String text) {
  final rtlRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\u0590-\u05FF]');
  final ltrRegex = RegExp(r'[A-Za-z]');
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (rtlRegex.hasMatch(ch)) return TextDirection.rtl;
    if (ltrRegex.hasMatch(ch)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}
