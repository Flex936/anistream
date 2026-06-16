import 'dart:ui';

abstract final class AppPalette {
  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const Color base = Color(0xFF0A0A0C);
  static const Color surface = Color(0xFF14151A);
  static const Color overlay = Color(0xFF1C1D24);
  static const Color border = Color(0xFF272A35);

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryHover = Color(0xFF4F46E5);
  static const Color accent = Color(0xFFFBBF24);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textMain = Color(0xFFF1F5F9);
  static const Color textMuted = Color(0xFF94A3B8);

  // ── Status badges ────────────────────────────────────────────────────────
  static const Color statusReleasing = Color(0xFF4ADE80);
  static const Color statusFinished = Color(0xFF38BDF8);
  static const Color statusCancelled = Color(0xFFF87171);
  static const Color statusHiatus = Color(0xFFFB923C);
  static const Color statusDefault = Color(0xFF94A3B8);
}
