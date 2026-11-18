# Cinemakom

A cross-platform streaming frontend (Android, iOS, Linux, Windows) for the Cinemana API, written in Flutter.
English and Arabic are supported. English is the default, and Arabic switches the layout to RTL.

- `docs/PLAN.md`: architecture, tech stack, features and build phases
- `docs/API.md`: endpoints, required headers and JSON quirks
- `AGENTS.md`: rules for contributors and AI agents

## Develop
```bash
flutter pub get          # also generates the localization classes
flutter analyze
flutter test
flutter run -d linux     # Linux needs libmpv: sudo pacman -S mpv
```
