# Gethics Flutter App

Aplicación móvil multiplataforma de **Gethics** (equipo JamSell, curso 1ACC0238 Aplicaciones para Dispositivos Móviles, UPC), enfocada en el flujo del **veterinario**.

Consume los Web Services de `gethics-backend`.

## Ramas

- `main`: versión estable.
- `develop`: integración de las historias de usuario.
- `feature/US-<número>-<descripción>`: una rama por historia, integrada a `develop` mediante Pull Request.

## Requisitos

- Flutter 3.50.1 (canal stable), Dart 3.14.
- Android Studio con un emulador, o un dispositivo Android.

## Cómo ejecutar

```bash
flutter pub get
flutter run
```

Por defecto la app usa el backend desplegado en staging (`https://gethics-backend-staging-7qth.onrender.com/`). Para usar el backend local desde el emulador de Android:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/
```

## Verificaciones

```bash
flutter analyze
flutter test
```

El workflow `CI` de GitHub Actions ejecuta ambas en cada push y Pull Request a `develop` y `main`.

## Estructura

```
lib/
├── main.dart                  # arranque: crea las dependencias y lanza la app
├── app.dart                   # MaterialApp, tema, idiomas y rutas
├── core/
│   ├── config/                # URL base del backend y tiempo de espera
│   ├── network/               # ApiClient (JSON, token JWT, errores del backend) y ApiException
│   ├── session/               # SessionStorage (token, rol y nombre en el dispositivo)
│   ├── common/                # Result (Success / Failure) para los repositorios
│   ├── theme/                 # colores de los Style Guidelines de Gethics
│   └── di/                    # AppDependencies: repositorios compartidos
├── features/                  # un módulo por bounded context
│   ├── iam/                   # inicio de sesión
│   │   ├── data/              # repositorios y acceso a la API
│   │   ├── domain/            # modelos
│   │   └── presentation/      # pantallas (Page) y ViewModels (ChangeNotifier)
│   ├── livestock/             # animales: lista con búsqueda y filtros por estado, y ficha con su granja
│   └── veterinary/            # inicio del flujo veterinario (Clientes, Calendario, Animales, Perfil)
├── shared/widgets/            # estados de carga, error con reintento y vacío
└── l10n/                      # textos en español (app_es.arb) e inglés (app_en.arb)
test/                          # pruebas con la misma estructura de lib/
```

## Convenciones

- **Arquitectura:** MVVM por feature. La pantalla observa un `ChangeNotifier` (paquete `provider`); el ViewModel usa un repositorio que devuelve `Result` y nunca lanza excepciones a la pantalla.
- **Textos:** siempre en `lib/l10n/app_es.arb` y `lib/l10n/app_en.arb`; nunca escritos directamente en el código. `flutter pub get` genera `AppLocalizations`.
- **API:** los repositorios usan el `ApiClient` compartido de `AppDependencies`, que agrega el token de la sesión.
- **Commits:** Conventional Commits (`feat(sanitary): ...`, `test(iam): ...`, `docs: ...`).
- **Ramas:** una por historia de usuario, `feature/US-<número>-<descripción>`, creada desde `develop` e integrada con Pull Request.
