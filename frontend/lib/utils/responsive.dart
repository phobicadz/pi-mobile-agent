import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen size categories for responsive design
enum ScreenSize { phone, tablet, desktop }

/// Responsive design utilities for consistent breakpoints and sizing across screens
class ResponsiveSizes {
  ResponsiveSizes._(); // Private constructor to prevent instantiation

  // ============================================================================
  // Breakpoints
  // ============================================================================

  /// Below this width, the screen is considered a phone
  static const double phoneMaxWidth = 600.0;

  /// Below this width but above phoneMaxWidth, the screen is considered a tablet
  static const double tabletMaxWidth = 900.0;

  /// At or above this width, the screen is considered desktop
  static const double desktopThreshold = 900.0;

  // ============================================================================
  // Chat Bubble Constraints
  // ============================================================================

  /// Maximum width for chat bubbles on phones (full width with list padding)
  static const double chatMaxWidthPhone = double.infinity;

  /// Maximum width for chat bubbles on tablets
  static const double chatMaxWidthTablet = 700.0;

  /// Maximum width for chat bubbles on desktops
  static const double chatMaxWidthDesktop = 800.0;

  // ============================================================================
  // Input Area Layout
  // ============================================================================

  /// Maximum width for the input area (model selector + text field + buttons)
  static const double inputAreaMaxWidth = 1000.0;

  /// Default horizontal padding for input area on tablets/desktops
  static const double inputAreaHorizontalPadding = 16.0;

  // ============================================================================
  // Standard Padding Values
  // ============================================================================

  /// Small padding for compact components
  static const double paddingSmall = 8.0;

  /// Standard padding for most components
  static const double paddingMedium = 12.0;

  /// Large padding for spacious layouts
  static const double paddingLarge = 16.0;

  /// Extra large padding for major spacing
  static const double paddingXLarge = 24.0;

  // ============================================================================
  // Classification Methods
  // ============================================================================

  /// Determines if the given width is a phone screen
  static bool isPhone(double width) => width < phoneMaxWidth;

  /// Determines if the given width is a tablet screen
  static bool isTablet(double width) =>
      width >= phoneMaxWidth && width < desktopThreshold;

  /// Determines if the given width is a desktop screen
  static bool isDesktop(double width) => width >= desktopThreshold;

  /// Categorizes the given width into a ScreenSize enum
  static ScreenSize getScreenSize(double width) {
    if (isPhone(width)) return ScreenSize.phone;
    if (isTablet(width)) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  // ============================================================================
  // Chat Bubble Sizing
  // ============================================================================

  /// Gets the appropriate max width for a chat bubble based on screen size
  /// and whether it's expanded
  static double getChatMaxWidth(
    double screenWidth, {
    bool expanded = false,
  }) {
    final screenSize = getScreenSize(screenWidth);

    if (expanded) {
      // Expanded bubbles take most of the screen
      return screenWidth * 0.95;
    }

    switch (screenSize) {
      case ScreenSize.phone:
        // Phones already have the list's padding accounted for
        return chatMaxWidthPhone;
      case ScreenSize.tablet:
        return chatMaxWidthTablet;
      case ScreenSize.desktop:
        return chatMaxWidthDesktop;
    }
  }

  // ============================================================================
  // Input Area Sizing
  // ============================================================================

  /// How far the prompt field reaches into the home-indicator band.
  ///
  /// The band is a swipe zone, not a dead zone, so the field reaches 12px into
  /// it instead of being pushed a whole inset above it.
  static const double inputBottomDip = 12.0;

  /// How clear of the very bottom the prompt field stays, where a tap would
  /// compete with the home gesture.
  static const double inputBottomFloor = 10.0;

  /// The bottom padding under the prompt field, from the inset the browser
  /// reported.
  ///
  /// This one is about the device, not the width: a phone in landscape is as
  /// wide as a tablet and still has a home indicator to keep clear of, so it is
  /// applied on every branch of [getInputAreaPadding]. With no inset reported
  /// there is nothing to dip into, and the floor is the whole margin.
  static double inputBottomInset(double reported) {
    if (reported <= 0) return inputBottomFloor;
    return math.max(inputBottomFloor, reported - inputBottomDip);
  }

  /// Calculates centered padding for the input area to center it on wide screens
  static EdgeInsets getInputAreaPadding(
    double screenWidth, {
    required EdgeInsets insets,
  }) {
    final screenSize = getScreenSize(screenWidth);

    if (screenSize == ScreenSize.phone) {
      // Phone: respect safe area insets
      return EdgeInsets.only(
        left: insets.left > 0 ? insets.left : paddingLarge,
        right: insets.right > 0 ? insets.right : paddingLarge,
        top: paddingMedium,
        bottom: inputBottomInset(insets.bottom),
      );
    }

    // Tablet/Desktop: center the input area
    final horizontalInset = insets.left > 0 ? insets.left : 0;
    final availableWidth = screenWidth - (2 * horizontalInset);
    final inputWidth = inputAreaMaxWidth;

    if (availableWidth > inputWidth) {
      // Screen is wider than max input width - center it
      final sidePadding = ((availableWidth - inputWidth) / 2) + horizontalInset;
      return EdgeInsets.only(
        left: sidePadding,
        right: sidePadding,
        top: paddingLarge,
        bottom: inputBottomInset(insets.bottom),
      );
    } else {
      // Screen is narrower than max width - use all available space
      return EdgeInsets.only(
        left: horizontalInset + paddingLarge,
        right: (insets.right > 0 ? insets.right : 0) + paddingLarge,
        top: paddingLarge,
        bottom: inputBottomInset(insets.bottom),
      );
    }
  }

  // ============================================================================
  // Font Sizing
  // ============================================================================

  /// Gets a responsive font size based on screen size
  /// [baseSize] is the font size for phone screens
  /// Returns scaled size for tablet/desktop
  static double getResponsiveFontSize(
    double baseSize, {
    double tabletMultiplier = 1.05,
    double desktopMultiplier = 1.1,
    required double screenWidth,
  }) {
    final screenSize = getScreenSize(screenWidth);

    switch (screenSize) {
      case ScreenSize.phone:
        return baseSize;
      case ScreenSize.tablet:
        return baseSize * tabletMultiplier;
      case ScreenSize.desktop:
        return baseSize * desktopMultiplier;
    }
  }

  // ============================================================================
  // Layout Direction Helpers
  // ============================================================================

  /// Returns true if the input area should be laid out horizontally
  /// (model selector on the left, input field on the right)
  static bool shouldUseHorizontalInputLayout(double screenWidth) =>
      !isPhone(screenWidth);

  /// Returns true if a split-view layout should be used (with navigation rail)
  static bool shouldUseSplitLayout(double screenWidth) =>
      isDesktop(screenWidth);

  // ============================================================================
  // Popup/Modal Sizing
  // ============================================================================

  /// Gets the appropriate height for a bottom sheet on different screens
  static double getBottomSheetHeight(
    double screenHeight, {
    required ScreenSize screenSize,
  }) {
    switch (screenSize) {
      case ScreenSize.phone:
        return screenHeight * 0.7;
      case ScreenSize.tablet:
        return screenHeight * 0.65;
      case ScreenSize.desktop:
        return screenHeight * 0.6;
    }
  }

  /// Gets the initial child size for a DraggableScrollableSheet
  static double getInitialDraggableSheetSize(ScreenSize screenSize) {
    switch (screenSize) {
      case ScreenSize.phone:
        return 0.7;
      case ScreenSize.tablet:
        return 0.65;
      case ScreenSize.desktop:
        return 0.6;
    }
  }
}

/// Extension methods for BuildContext to easily access responsive utilities
extension ResponsiveContext on BuildContext {
  /// Gets the current screen width
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Gets the current screen height
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Gets the current screen size category
  ScreenSize get screenSize => ResponsiveSizes.getScreenSize(screenWidth);

  /// Convenience check if screen is phone-sized
  bool get isPhone => ResponsiveSizes.isPhone(screenWidth);

  /// Convenience check if screen is tablet-sized
  bool get isTablet => ResponsiveSizes.isTablet(screenWidth);

  /// Convenience check if screen is desktop-sized
  bool get isDesktop => ResponsiveSizes.isDesktop(screenWidth);
}
