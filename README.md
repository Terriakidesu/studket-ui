# Studket

Studket is a Flutter marketplace for campus communities. It lets students post
items for sale, create “looking for” requests, chat with each other, and keep
up with notifications in one place.

## Highlights

- Browse a feed of listings with search, tags, and pagination
- Post listings as a seller or submit “looking for” requests
- View listing details with price, seller info, and media
- Chat and notification inbox with real-time badge counts
- Profile view with seller/buyer context

## Getting Started

### Prerequisites

- Flutter SDK (Dart 3.11+ as defined in `pubspec.yaml`)

### Run locally

```bash
flutter pub get
flutter run
```

### API configuration

The app talks to a backend API. By default it points at a dev tunnel host.
Override it for local or staging environments:

```bash
flutter run --dart-define=API_BASE_URL=https://your-host.example.com/api/v1
```

## Project layout

- `lib/` app UI, navigation, and API clients
- `lib/models/` data models for listings and profiles
- `lib/api/` API routes, session storage, and base URL helpers
- `assets/` static assets including the app icon

## Useful Flutter docs

- https://docs.flutter.dev/get-started/learn-flutter
- https://docs.flutter.dev/get-started/codelab
- https://docs.flutter.dev/reference/learning-resources
