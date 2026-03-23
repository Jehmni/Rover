// rover_theme.dart
// "The Intelligent Navigator" design system for Rover.
//
// Color palette: Forest Green (#006943) primary, Amber (#855300) accent.
// Font: Inter (via google_fonts).
// Philosophy: tonal layering over borders, soft minimalism.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────
// Color tokens
// ─────────────────────────────────────────────────────────────
class RoverColors {
  RoverColors._();

  // Primary — Forest Green
  static const primary              = Color(0xFF006943);
  static const primaryContainer     = Color(0xFFDCF5E7); // light green tint
  static const onPrimary            = Color(0xFFFFFFFF);
  static const onPrimaryContainer   = Color(0xFFEFFFF2);
  static const primaryFixed         = Color(0xFF91F7C0);

  // Secondary — Amber (intelligence / attention, NOT danger)
  static const secondary            = Color(0xFF855300);
  static const secondaryContainer   = Color(0xFFFFF3E0); // light amber tint
  static const onSecondary          = Color(0xFFFFFFFF);
  static const onSecondaryContainer = Color(0xFF684000);
  static const secondaryFixed       = Color(0xFFFFDDB8);

  // Tertiary — Muted Red (danger / error states only)
  static const tertiary             = Color(0xFF973E40);
  static const tertiaryContainer    = Color(0xFFB65657);
  static const onTertiaryContainer  = Color(0xFFFFFAF9);

  // Surface hierarchy (tonal layering — no harsh borders)
  static const surface              = Color(0xFFF8F9FB);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow  = Color(0xFFF3F4F6);
  static const surfaceContainer     = Color(0xFFEDEEF0);
  static const surfaceContainerHigh = Color(0xFFE5E7EB);
  static const surfaceContainerHighest = Color(0xFFE1E2E4);
  static const surfaceDim           = Color(0xFFD9DADC);

  // On-surface text
  static const onSurface            = Color(0xFF191C1E);
  static const onSurfaceVariant     = Color(0xFF3E4942);

  // Convenience aliases used across screens
  static const textPrimary          = onSurface;        // #191C1E
  static const textSecondary        = Color(0xFF6B7280); // medium gray

  // Outline
  static const outline              = Color(0xFF6E7A71);
  static const outlineVariant       = Color(0xFFBDCABF);

  // Error
  static const error                = Color(0xFFBA1A1A);
  static const errorContainer       = Color(0xFFFFDAD6);
  static const onError              = Color(0xFFFFFFFF);

  // Semantic status backgrounds (for pickup chips)
  static const statusPendingBg      = Color(0xFFDCF5E7);   // soft green tint
  static const statusPendingFg      = Color(0xFF005234);
  static const statusEnRouteBg      = Color(0xFFFFF3E0);   // soft amber tint
  static const statusEnRouteFg      = Color(0xFF653E00);
  static const statusCompletedBg   = Color(0xFFEDEEF0);   // neutral
  static const statusCompletedFg   = Color(0xFF3E4942);

  // Driver map pin colours
  static const pinPending           = Color(0xFF006943);
  static const pinEnRoute           = Color(0xFFFEA619);
  static const pinCompleted         = Color(0xFF9CA3AF);
}

// ─────────────────────────────────────────────────────────────
// Text styles (Inter)
// ─────────────────────────────────────────────────────────────
class RoverText {
  RoverText._();

  static TextStyle displayLg({Color? color}) => GoogleFonts.inter(
    fontSize: 48, fontWeight: FontWeight.w800, height: 1.1,
    letterSpacing: -1.5, color: color ?? RoverColors.onSurface,
  );

  static TextStyle headlineLg({Color? color}) => GoogleFonts.inter(
    fontSize: 32, fontWeight: FontWeight.w800, height: 1.2,
    letterSpacing: -0.5, color: color ?? RoverColors.onSurface,
  );

  static TextStyle headlineMd({Color? color}) => GoogleFonts.inter(
    fontSize: 24, fontWeight: FontWeight.w700, height: 1.3,
    color: color ?? RoverColors.onSurface,
  );

  static TextStyle headlineSm({Color? color}) => GoogleFonts.inter(
    fontSize: 20, fontWeight: FontWeight.w700, height: 1.35,
    color: color ?? RoverColors.onSurface,
  );

  static TextStyle titleLg({Color? color}) => GoogleFonts.inter(
    fontSize: 18, fontWeight: FontWeight.w600, height: 1.4,
    color: color ?? RoverColors.onSurface,
  );

  static TextStyle titleMd({Color? color}) => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w600, height: 1.4,
    color: color ?? RoverColors.onSurface,
  );

  static TextStyle titleSm({Color? color}) => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w600, height: 1.5,
    color: color ?? RoverColors.onSurface,
  );

  static TextStyle bodyMd({Color? color}) => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.6,
    color: color ?? RoverColors.onSurfaceVariant,
  );

  static TextStyle bodySm({Color? color}) => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w400, height: 1.5,
    color: color ?? RoverColors.onSurfaceVariant,
  );

  static TextStyle labelMd({Color? color}) => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w600, height: 1.3,
    letterSpacing: 0.3, color: color ?? RoverColors.onSurfaceVariant,
  );

  static TextStyle labelSm({Color? color}) => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w600, height: 1.2,
    letterSpacing: 0.5, color: color ?? RoverColors.onSurfaceVariant,
  );
}

// ─────────────────────────────────────────────────────────────
// ThemeData
// ─────────────────────────────────────────────────────────────
class RoverTheme {
  RoverTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary:            RoverColors.primary,
      onPrimary:          RoverColors.onPrimary,
      primaryContainer:   RoverColors.primaryContainer,
      onPrimaryContainer: RoverColors.onPrimaryContainer,
      secondary:          RoverColors.secondary,
      onSecondary:        RoverColors.onSecondary,
      secondaryContainer: RoverColors.secondaryContainer,
      onSecondaryContainer: RoverColors.onSecondaryContainer,
      tertiary:           RoverColors.tertiary,
      onTertiary:         RoverColors.onTertiaryContainer,
      tertiaryContainer:  RoverColors.tertiaryContainer,
      onTertiaryContainer: RoverColors.onTertiaryContainer,
      error:              RoverColors.error,
      onError:            RoverColors.onError,
      errorContainer:     RoverColors.errorContainer,
      onErrorContainer:   const Color(0xFF93000A),
      surface:            RoverColors.surface,
      onSurface:          RoverColors.onSurface,
      onSurfaceVariant:   RoverColors.onSurfaceVariant,
      outline:            RoverColors.outline,
      outlineVariant:     RoverColors.outlineVariant,
      shadow:             Colors.black,
      scrim:              Colors.black,
      inverseSurface:     const Color(0xFF2E3132),
      onInverseSurface:   const Color(0xFFF0F1F3),
      inversePrimary:     const Color(0xFF75DAA6),
      surfaceTint:        RoverColors.primary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: RoverColors.surface,
      fontFamily: GoogleFonts.inter().fontFamily,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: RoverColors.surfaceContainerLowest,
        foregroundColor: RoverColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        titleTextStyle: RoverText.titleLg(),
        iconTheme: const IconThemeData(color: RoverColors.onSurface),
      ),

      // Cards — no border, tonal surface, diffused shadow
      cardTheme: CardThemeData(
        color: RoverColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
      ),

      // Elevated button — filled primary, no border
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: RoverColors.primary,
          foregroundColor: RoverColors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: RoverText.titleSm(color: RoverColors.onPrimary),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RoverColors.primary,
          side: const BorderSide(color: RoverColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: RoverText.titleSm(color: RoverColors.primary),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RoverColors.primary,
          textStyle: RoverText.labelMd(color: RoverColors.primary),
        ),
      ),

      // Input fields — no border, tonal fill
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RoverColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RoverColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RoverColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RoverColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RoverColors.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RoverColors.error, width: 2),
        ),
        labelStyle: RoverText.bodyMd(),
        hintStyle: RoverText.bodyMd(color: RoverColors.outline),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: RoverColors.surfaceContainerLow,
        labelStyle: RoverText.labelSm(),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // Divider — subtle, almost invisible
      dividerTheme: const DividerThemeData(
        color: RoverColors.surfaceContainerHigh,
        thickness: 1,
        space: 0,
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: RoverColors.surfaceContainerLowest,
        selectedItemColor: RoverColors.primary,
        unselectedItemColor: RoverColors.outline,
        selectedLabelStyle: RoverText.labelSm(color: RoverColors.primary),
        unselectedLabelStyle: RoverText.labelSm(color: RoverColors.outline),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RoverColors.onSurface,
        contentTextStyle: RoverText.bodyMd(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────

/// Status chip with traffic-light colour logic.
class RoverStatusChip extends StatelessWidget {
  final String status;
  const RoverStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'en_route'  => (RoverColors.statusEnRouteBg,  RoverColors.statusEnRouteFg,  'En Route'),
      'completed' => (RoverColors.statusCompletedBg, RoverColors.statusCompletedFg, 'Picked Up'),
      _           => (RoverColors.statusPendingBg,  RoverColors.statusPendingFg,  'Waiting'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: RoverText.labelSm(color: fg)),
    );
  }
}

/// Full-width primary action button (optionally amber for high-urgency driver actions).
class RoverPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool amber;
  final IconData? icon;

  const RoverPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.amber = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = amber ? RoverColors.secondaryContainer : RoverColors.primary;
    final fg = amber ? RoverColors.onSecondaryContainer : RoverColors.onPrimary;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: RoverText.titleMd(color: fg),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: fg,
                ),
              )
            : icon != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 8),
                      Text(label),
                    ],
                  )
                : Text(label),
      ),
    );
  }
}

/// Outlined secondary button (full width).
class RoverOutlinedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const RoverOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        child: icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              )
            : Text(label),
      ),
    );
  }
}

/// ETA card shown on attendee's event detail and driver screens.
class RoverEtaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accentColor;

  const RoverEtaCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? RoverColors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,   style: RoverText.titleSm(color: RoverColors.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle, style: RoverText.bodySm()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Surface card with optional left accent stripe (used on role cards & event rows).
class RoverAccentCard extends StatelessWidget {
  final Widget child;
  final Color? accentColor;
  final VoidCallback? onTap;

  const RoverAccentCard({
    super.key,
    required this.child,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: RoverColors.surfaceContainerLowest,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                if (accentColor != null)
                  Container(width: 4, color: accentColor),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
