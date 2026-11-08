# TrainHub

Flutter client for TrainHub (`com.nbek.trainhub`).

Starter based on [flutter_base](https://github.com/nbekuz/flutter_base).

## Stack

| Layer | Package |
| --- | --- |
| Networking | dio |
| State | flutter_riverpod |
| DI | get_it |
| Routing | go_router |
| Storage | shared_preferences |

## Run

```bash
flutter pub get
flutter run

# Environments
flutter run --dart-define=ENV=development
flutter run --dart-define=ENV=staging
flutter run --dart-define=ENV=production
```

Base URL: `lib/core/config/api_config.dart`
