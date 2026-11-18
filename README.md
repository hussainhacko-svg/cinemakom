# Cinemakom

A cross-platform streaming frontend (Android, iOS, Linux, Windows) for the Cinemana API, written in Flutter.
English and Arabic are supported. English is the default, and Arabic switches the layout to RTL.

- `AGENTS.md`: rules for contributors and AI agents (read first)
- `docs/API.md`: the reverse-engineered API (endpoints, parameters, limits, data shapes)
- `docs/DESIGN.md`: the "Marquee" design system, the logo and how the icons are generated
- `docs/PLAN.md`: architecture, features, phases and current status

## Develop
The project is pinned to **Flutter 3.47.9** with [fvm](https://fvm.app) (`.fvmrc`), so always use `fvm flutter`:
```bash
fvm flutter pub get          # also generates the localization classes
fvm flutter analyze
fvm flutter test
fvm flutter run -d linux     # Linux needs libmpv: sudo pacman -S mpv
fvm dart run tool/api_contract_check.dart   # check the live API still matches docs/API.md
python3 tool/brand/generate.py              # regenerate the logo and all app icons
```
