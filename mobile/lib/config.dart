/// Set with --dart-define=API_BASE_URL=... for the target device.
/// Android Emulator reaches the host machine through 10.0.2.2.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
