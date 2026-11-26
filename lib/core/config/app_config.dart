/// URL base de los Web Services. Por defecto el backend desplegado en staging; se puede cambiar al compilar con
/// `--dart-define=API_BASE_URL=http://10.0.2.2:8080/` (backend local desde el emulador de Android).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://gethics-backend-staging-7qth.onrender.com/',
);

/// Tiempo maximo de espera de una solicitud: el servidor de staging puede tardar en despertar.
const Duration apiTimeout = Duration(seconds: 30);
