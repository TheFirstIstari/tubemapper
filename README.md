# TubeMapper

Crowd-sourced 3D reconstruction of underground rail systems from phone sensor data.

## Project Structure

```
tubemapper/
├── mobile/                  # Flutter app (Dart)
│   └── lib/services/        # Sensor recording, geofence, API client
├── render-server/           # Rust render server (Axum)
│   └── src/
│       ├── main.rs          # API routes: /status, /trace, /model
│       ├── model.rs         # Tube graph, network definition, trace types
│       └── pipeline.rs      # Per-trace processing stub
├── shared/                  # Shared schemas (protobuf)
├── NetworkDefinitions/      # JSON network definitions (any rail system)
└── .mise.toml               # Rust toolchain via mise
```

## Collecting the First Trace

**1. Start the server**
```bash
cd render-server
cargo run
# -> listening on 0.0.0.0:3000
```

**2. Find your machine's LAN IP**
```bash
ipconfig getifaddr en0   # macOS
# -> 192.168.1.X
```

**3. Set the server URL in the app**
Edit `mobile/lib/main.dart` line 43 — change `_serverUrl` to your machine's IP:
```dart
static const String _serverUrl = 'http://192.168.1.X:3000';
```

**4. Run the app on a device**
```bash
cd mobile
flutter run
```

**5. Record a journey**
- Tap **Start Manual** at the station you're at
- Ride one stop
- Tap **Stop**
- The trace uploads automatically

**6. Verify**
```bash
curl http://localhost:3000/api/v1/status
# -> total_traces: 1, model_revision: 1
```

## Auto-Start

The app can automatically start recording when you enter a station:
- Uses GPS geofencing around known station positions
- Starts recording on entry, stops on exit to a different station
- Tap **Auto-Detect** to enable

## Adding a New Network

Drop a JSON file into `NetworkDefinitions/` following the schema in `london-underground.json`. No code changes needed.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TUBEMAPPER_NETWORK` | `../NetworkDefinitions/london-underground.json` | Network definition path |

## CI / CD

Every push to `main` and every tag `v*` triggers GitHub Actions:

| Workflow | Trigger | Artifacts |
|----------|---------|-----------|
| `flutter analyze` | Every PR + push | Lint results |
| Android APK | Push to main + tags | `tubemapper-android-debug.apk` |
| iOS debug | Push to main + tags | `Runner.app` (unsigned) |
| Release | Tag `v*` | GitHub Release with APK + iOS app |

**Release a new version:**
```bash
# Bump the version number in pubspec.yaml
make bump

# Tag and push — GitHub Actions builds + attaches the artifacts
make release
```

The release workflow builds both Android APK and iOS debug builds, attaches them to a GitHub Release, and auto-generates release notes from commits.

**For CI:** The server URL is injected via `--dart-define=SERVER_URL=...`. Set it in `.github/workflows/build.yml` under `env.SERVER_URL` for your production server address.

## Privacy

- No user accounts — ephemeral device tokens only
- All traces deletable by the user
- Sensor data encrypted in transit (TLS 1.3)
- No telemetry or analytics
