# UI Responsiveness Improvements

This document outlines recommended improvements to make the pi-mobile-agent more responsive across different screen sizes (phones, tablets, desktops).

## Current Issues

1. **Limited screen size breakpoints** - Only distinguishes phones (<600dp) from larger screens
2. **Fixed input area layout** - Model selector, text field, and buttons use same layout on all screen sizes
3. **Drawer navigation only** - No tablet/desktop-specific navigation patterns
4. **Underutilized horizontal space** - Especially on tablets and wide displays
5. **Chat bubbles not fully optimized** - Could use more sophisticated max-width logic

## Recommended Changes

### 1. Add Responsive Layout Constants
**File:** `frontend/lib/utils/responsive.dart` (new file)

Define consistent breakpoints and screen size categories:
- Phone: < 600dp
- Tablet: 600-900dp  
- Desktop: >= 900dp

```dart
class ResponsiveSizes {
  // Breakpoints
  static const double phoneMaxWidth = 600.0;
  static const double tabletMaxWidth = 900.0;
  
  // Screen categories
  static const double mobileThreshold = 600.0;
  static const double tabletThreshold = 900.0;
  static const double desktopThreshold = 1200.0;
  
  // Chat bubble constraints
  static const double chatMaxWidthPhone = double.infinity; // Full width
  static const double chatMaxWidthTablet = 700.0;
  static const double chatMaxWidthDesktop = 800.0;
  
  // Input area layout
  static const double inputAreaMaxWidth = 1000.0;
  
  static bool isPhone(double width) => width < mobileThreshold;
  static bool isTablet(double width) => width >= mobileThreshold && width < tabletThreshold;
  static bool isDesktop(double width) => width >= tabletThreshold;
  
  static ScreenSize getScreenSize(double width) {
    if (isPhone(width)) return ScreenSize.phone;
    if (isTablet(width)) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }
}

enum ScreenSize { phone, tablet, desktop }
```

### 2. Update HomeScreen for Adaptive Layout
**File:** `frontend/lib/screens/home_screen.dart`

Key improvements:
- Use responsive layout for input area on tablets/desktops
- Better utilize horizontal space
- Adaptive drawer vs. rail navigation

```dart
// Add to _HomeScreenState class:

Widget _buildAdaptiveNavigation() {
  // Return drawer on mobile, navigation rail on tablets/desktops
  // This would require additional refactoring
}

Widget _buildResponsiveInputArea(BuildContext context, PiViewModel viewModel) {
  final screenSize = ResponsiveSizes.getScreenSize(MediaQuery.of(context).size.width);
  final width = MediaQuery.of(context).size.width;
  final insets = MediaQuery.of(context).padding;
  
  // Phone: vertical stack (current behavior)
  if (screenSize == ScreenSize.phone) {
    return _buildPhoneInputArea(context, viewModel, insets);
  }
  
  // Tablet/Desktop: horizontal layout for better space utilization
  if (screenSize == ScreenSize.tablet || screenSize == ScreenSize.desktop) {
    return _buildWideInputArea(context, viewModel, insets);
  }
  
  return _buildPhoneInputArea(context, viewModel, insets);
}

Widget _buildPhoneInputArea(BuildContext context, PiViewModel viewModel, EdgeInsets insets) {
  // Current vertical layout
  final panelPadding = EdgeInsets.only(
    left: math.max(16.0, insets.left),
    right: math.max(16.0, insets.right),
    top: 16,
    bottom: math.max(10.0, insets.bottom - 12),
  );
  
  return Container(
    padding: panelPadding,
    child: Column(
      children: [
        const ModelSelector(),
        const SizedBox(height: 12),
        _buildInputRow(context, viewModel),
      ],
    ),
  );
}

Widget _buildWideInputArea(BuildContext context, PiViewModel viewModel, EdgeInsets insets) {
  // Tablet/Desktop: model selector above, input row below, with max width
  final maxWidth = ResponsiveSizes.inputAreaMaxWidth;
  final horizontalPadding = math.max(16.0, (MediaQuery.of(context).size.width - maxWidth) / 2);
  
  final panelPadding = EdgeInsets.only(
    left: horizontalPadding,
    right: horizontalPadding,
    top: 16,
    bottom: math.max(10.0, insets.bottom - 12),
  );
  
  return Container(
    padding: panelPadding,
    child: Column(
      children: [
        SizedBox(
          width: maxWidth,
          child: const ModelSelector(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: maxWidth,
          child: _buildInputRow(context, viewModel),
        ),
      ],
    ),
  );
}

Widget _buildInputRow(BuildContext context, PiViewModel viewModel) {
  // Extract current input row logic
  return Row(
    children: [
      Expanded(
        child: Focus(
          onKeyEvent: (node, event) {
            // Current key handling
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
              if (HardwareKeyboard.instance.isControlPressed ||
                  context.read<PiViewModel>().isLoading) {
                return KeyEventResult.ignored;
              }
              _sendPrompt(context.read<PiViewModel>());
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _inputController,
            focusNode: _inputFocus,
            onChanged: viewModel.setUserInput,
            maxLines: null,
            decoration: InputDecoration(
              hintText: 'Enter a prompt or command...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (viewModel.isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.red,
                onPressed: viewModel.abortCurrentTask,
                child: const Icon(Icons.stop),
              ),
            ),
          FloatingActionButton(
            mini: true,
            onPressed: viewModel.isLoading ? null : () => _sendPrompt(viewModel),
            child: const Icon(Icons.send),
          ),
        ],
      ),
    ],
  );
}
```

### 3. Update ChatBubble for Better Max-Width
**File:** `frontend/lib/widgets/chat_bubble.dart`

```dart
// Replace the max-width calculation:

final screenWidth = MediaQuery.sizeOf(context).width;
final screenSize = ResponsiveSizes.getScreenSize(screenWidth);
final phone = screenSize == ScreenSize.phone;

// Better max-width logic based on screen size
double getMaxWidth() {
  switch (screenSize) {
    case ScreenSize.phone:
      return screenWidth; // Full width
    case ScreenSize.tablet:
      return math.min(700.0, screenWidth * 0.85);
    case ScreenSize.desktop:
      return math.min(800.0, screenWidth * 0.75);
  }
}

final maxWidth = expanded ? screenWidth * 0.95 : getMaxWidth();
```

### 4. Add Responsive Drawer/Navigation Rail
**File:** `frontend/lib/screens/home_screen.dart`

For tablets/desktops, consider a split-view or navigation rail:

```dart
@override
Widget build(BuildContext context) {
  final screenSize = ResponsiveSizes.getScreenSize(MediaQuery.of(context).size.width);
  
  if (screenSize == ScreenSize.phone) {
    return _buildPhoneLayout();
  } else {
    return _buildTabletLayout();
  }
}

Widget _buildTabletLayout() {
  // Split-view with drawer as a permanent side panel
  // or use NavigationRail for the left side
  return Row(
    children: [
      NavigationRail(
        // Configuration here
      ),
      Expanded(
        child: _buildMainContent(),
      ),
    ],
  );
}
```

### 5. Improve Model Selector for Different Screens
**File:** `frontend/lib/widgets/model_selector.dart`

```dart
// Make the dropdown more responsive:

Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isCompactMode = screenWidth < 600;
  
  // ... existing code ...
  
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(8),
    ),
    child: isCompactMode 
      ? _buildCompactDropdown(...)
      : _buildStandardDropdown(...),
  );
}
```

### 6. Improve Error Message Display
**File:** `frontend/lib/screens/home_screen.dart`

```dart
// Make error message adaptive:

if (viewModel.error != null)
  Container(
    constraints: BoxConstraints(
      maxWidth: ResponsiveSizes.inputAreaMaxWidth,
    ),
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: Colors.red.shade100,
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            viewModel.error!,
            style: TextStyle(color: Colors.red.shade900),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, color: Colors.red.shade900),
          onPressed: viewModel.clearError,
        ),
      ],
    ),
  ),
```

## Implementation Priority

1. **High Priority** (immediate)
   - Add `responsive.dart` utility file
   - Update `chat_bubble.dart` for better max-width logic
   - Update `home_screen.dart` input area layout

2. **Medium Priority** (improves experience)
   - Improve error message display
   - Enhance model selector for tablets
   - Add adaptive font sizing for headers/buttons

3. **Low Priority** (future enhancements)
   - Implement NavigationRail for tablets/desktops
   - Add true split-view layout for wide screens
   - Implement master-detail view for session list

## Testing Strategy

Test on:
- Small phone (375dp width)
- Large phone (600dp width)
- Tablet (768dp width)
- Tablet landscape (1024dp width)
- Desktop (1200dp+ width)

Use `flutter run -d chrome --web-renderer=html` to test at different viewport sizes.

## Expected Benefits

- **Better space utilization** on tablets and desktops
- **Improved readability** with optimized chat bubble widths
- **More consistent experience** across device sizes
- **Future-proof architecture** for additional screen-size-specific features
- **Easier maintenance** with centralized responsive breakpoints
