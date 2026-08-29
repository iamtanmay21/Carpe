# Flutter

A modern Flutter-based mobile application utilizing the latest mobile development technologies and tools for building responsive cross-platform applications.

## ð Prerequisites

- Flutter SDK (^3.38.4)
- Dart SDK
- Android Studio / VS Code with Flutter extensions
- Android SDK / Xcode (for iOS development)

## ð ï¸ Installation

1. Install dependencies:
```bash
flutter pub get
```

2. Run the application:
```bash
flutter run
```

## ð Project Structure

```
flutter_app/
âââ android/            # Android-specific configuration
âââ ios/                # iOS-specific configuration
âââ lib/
â   âââ core/           # Core utilities and services
â   â   âââ utils/      # Utility classes
â   âââ presentation/   # UI screens and widgets
â   â   âââ splash_screen/ # Splash screen implementation
â   âââ routes/         # Application routing
â   âââ theme/          # Theme configuration
â   âââ widgets/        # Reusable UI components
â   âââ main.dart       # Application entry point
âââ assets/             # Static assets (images, fonts, etc.)
âââ pubspec.yaml        # Project dependencies and configuration
âââ README.md           # Project documentation
```

## ð§© Adding Routes

To add new routes to the application, update the `lib/routes/app_routes.dart` file:

```dart
import 'package:flutter/material.dart';
import 'package:package_name/presentation/home_screen/home_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String home = '/home';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const SplashScreen(),
    home: (context) => const HomeScreen(),
    // Add more routes as needed
  }
}
```

## ð¨ Theming

This project includes a comprehensive theming system with both light and dark themes:

```dart
// Access the current theme
ThemeData theme = Theme.of(context);

// Use theme colors
Color primaryColor = theme.colorScheme.primary;
```

The theme configuration includes:
- Color schemes for light and dark modes
- Typography styles
- Button themes
- Input decoration themes
- Card and dialog themes

## ð± Responsive Design

The app is built with responsive design using the Sizer package:

```dart
// Example of responsive sizing
Container(
  width: 50.w, // 50% of screen width
  height: 20.h, // 20% of screen height
  child: Text('Responsive Container'),
)
```
## ð¦ Deployment

Build the application for production:

```bash
# For Android
flutter build apk --release

# For iOS
flutter build ios --release
```