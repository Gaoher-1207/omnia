# Omnia Flutter app

The Flutter app in this directory is the canonical Omnia client for Android and web.
For API mode, it talks only to an Omnia API server; backend and model credentials must
remain on that server.

## Local web development

From this directory, run mock mode with `flutter run -d chrome`. To exercise a local
API server, copy `integration/omnia.env.example` to the git-ignored
`integration/omnia.env`, set `OMNIA_DATA=api` and
`OMNIA_API_BASE_URL=http://localhost:8000/api`, then run
`flutter run -d chrome --web-port 5173 --dart-define-from-file=integration/omnia.env`.
The backend must allow the local web origin in its CORS configuration.

## Production web build

Build a frontend configured for a hosted API with:

```bash
flutter build web --release \
  --dart-define=OMNIA_DATA=api \
  --dart-define=OMNIA_API_BASE_URL=https://api.example.com/api
```

The URL is public client configuration compiled into JavaScript. Never put API keys,
database credentials, or other server secrets in a `--dart-define` or web asset.
Without a configured API URL, a release build does not silently connect to localhost.

## Deploy to Vercel

Create a Vercel project for the Omnia repository and set **Root Directory** to
`Shehwaar/omnia_ui`. The checked-in `vercel.json` selects the custom Flutter build,
publishes `build/web`, and sends app paths through Flutter's `index.html` shell while
leaving real static assets available at their original paths.

Vercel settings: **Framework Preset: Other**, **Build Command:** `bash ./vercel-build.sh`,
**Output Directory:** `build/web`, **Install Command:** `bash ./vercel-build.sh --install`.
The checked-in `vercel.json` sets all four, so no dashboard overrides are needed.

Set these Vercel project environment variables for Production (and Preview if desired):

| Variable | Value |
|---|---|
| `OMNIA_API_BASE_URL` | Public HTTPS URL for the hosted API, including `/api` |
| `FLUTTER_VERSION` | Optional Flutter Git tag; omit to use the current `stable` channel |

The build script installs the Flutter SDK in Vercel's Linux build environment and runs
`flutter build web --release`. The API URL is passed as a compile-time define. After
setting the root directory and variables, deploy through the Vercel dashboard or CLI.
Do not set backend secrets in this frontend project.

## What a deployment includes

The Vercel deployment hosts only the Flutter web client. To use real accounts and synced
data, host the Omnia API separately, configure its `CORS_ORIGINS` allow-list for the
deployed web origin, and provide its HTTPS `/api` URL above. The reference API's assistant and plan
providers can call Ollama on the backend host; a user's PC or browser Ollama instance is
not contacted by the PWA. For a PC-independent deployment, the API, database, and any
enabled Ollama model runtime must run on hosted infrastructure. If AI is disabled or its
provider is unavailable, Omnia reports the service failure through its existing API
behavior; this web deployment does not substitute another model provider.

API mode stores the session token through `flutter_secure_storage`'s WebCrypto-backed
browser storage for that origin. Use HTTPS in production. Mock mode is available for
local UI development and does not sync data to a backend.
