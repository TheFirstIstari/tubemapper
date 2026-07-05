# Flutter App Audit

## Bug: GeofenceTrigger stream subscriptions never cancelled
`geofence_trigger.dart` — `_positionStream` subscription is created in `start()` but never cancelled in `dispose()`. The subscription callback also references `_hasStartedJourney` and `_currentJourneyStartStation` which can be stale after `dispose()`. Memory leak.

## Bug: SensorRecorder stream subscriptions leaked
`sensor_recorder.dart` — Accelerometer, gyroscope, and magnetometer event subscriptions are never cancelled. The `stop()` method clears the sample buffer but doesn't cancel the stream subscriptions. Multiple `start()` calls would create duplicate subscriptions.

## Bug: Hardcoded server URL
`main.dart:12` — `String.fromEnvironment('SERVER_URL', defaultValue: 'http://localhost:3000')` — This works for CI builds but runtime changes to the URL in the Settings screen are lost on restart. No persistence of user-configured URL.

## Bug: Empty station list in Settings tab
`main.dart:208` — The Settings tab calls `_loadNetwork()` via `_init()`. If the server is unreachable or returns an error, `_stations` remains empty. The station list is populated only if `_init()` completes before the user navigates to the Settings tab.

## Bug: No error handling for API calls
`api_client.dart` — All HTTP requests use `.catchError()` without propagating error details to the UI. If the server is unreachable, the app silently shows stale/empty data with no user feedback.

## Bug: Recording state not persisted
`main.dart` — Manual recording start/stop state is in-memory only. If the app is backgrounded and killed, the recording half-completes and no data is uploaded. No foreground service configured.

## Bug: Geofence radius mismatch
`geofence_trigger.dart:45` — Geofence trigger radius defaults to 200m. Many London Underground stations have entrances within 100m of each other (e.g., Bank/Monument, stations on the Circle line). At 200m radius, overlapping geofences will auto-trigger on the wrong station.

## Bug: Station list in Settings uses local asset file
`main.dart:75` — `_loadNetwork()` tries `_api.loadLocalNetwork()` first, but network data in `assets/london-underground.json` (78KB) is an older version than `NetworkDefinitions/london-underground.json` (114KB). Station IDs may not match the server's network definition, causing uploads with station IDs the server doesn't recognize.

## Design: No network error feedback
None of the screens show a loading indicator or error banner when API calls fail. A user with the app open but server down sees stale data with no indication.

## Design: No trace upload progress
When a trace finishes recording, `SensorRecorder.upload()` fires and forgets. For long journeys with thousands of samples, the upload might take seconds with no progress indicator.

## Design: Hardcoded max samples
`sensor_recorder.dart` — `_samples` list grows unbounded during recording. A long journey (30+ minutes at 25Hz) produces 45,000+ samples. No memory management strategy (ring buffer, periodic flush).

## Design: No app lifecycle handling
`main.dart` — No `WidgetsBindingObserver` to pause/resume recording when the app is backgrounded or locked.
