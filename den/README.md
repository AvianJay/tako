# Tako Den

A server you run yourself, for Tako: accounts, sync and models in one place.
Optional: Tako works fully without it.

- **Accounts.** An administrator and users, each with their own chats.
  Sign in with a password, or with Google, Discord, GitHub or any OpenID
  Connect provider (Authentik, Keycloak…). Registration can be closed, by
  invite, or open.
- **Sync.** Conversations, memory and personalization follow the account to
  every device, in the same JSON the app stores. Signing in on a phone that
  already has chats merges them into the account. Incognito chats, API keys,
  automations and device-control settings stay on the device.
- **Models.** The administrator adds model providers (OpenAI, OpenRouter,
  Ollama on your own computer…) and decides who may use them, with an
  optional daily token limit per user. Users can also add their own
  providers, which only they see. Phones never receive a provider's API key.
- **Web app.** Chat from a browser, with the same chats as your phone;
  manage your devices, your providers and, as administrator, the server.

All state is one SQLite file and a secret key under `data/`.

## Run it

With Docker:

```sh
docker compose up -d
```

using [docker-compose.yml](docker-compose.yml), or:

```sh
docker build -t tako-den .
docker run -d --name tako-den -p 8787:8787 -v tako-data:/data tako-den
```

Without Docker (Dart 3.11):

```sh
dart pub get
dart run bin/tako_den.dart
```

`dart build cli` writes a standalone executable and its SQLite library to
`build/cli/bundle`.

On first start the server prints a one-time link:

```
Open http://localhost:8787/setup?token=… to create the administrator.
```

Open it (on another machine, replace `localhost` with the server's address)
and create the administrator. Or set `TAKO_ADMIN_PASSWORD` to create
`admin` with that password at start-up instead.

## Connect the app

In Tako, tap **Or connect to Den…** on the first screen, or open
**Settings → Tako Den**, and enter the server's address. Then sign in:

- **Sign in with a browser** opens the Den in your browser, where you sign in
  however you like (password or OAuth) and confirm the code the app shows.
- **Username and password**, or **Create an account** when registration is
  open (or with an invite code).
- **Enter a pairing code** made on the web page under **Devices and API
  keys**, for a phone that has no browser session.

After signing in, the app uploads what is already on the phone, then keeps it
in sync; the Den's models appear as a provider named after the server.
Signing out keeps the chats on the phone.

Other apps can use the model gateway too: create an API key on the web page
and use `http://<server>:8787/v1` as an OpenAI-compatible base URL.

## Reach it from your phone

- **At home:** the server's LAN address, e.g. `192.168.1.20:8787`.
- **Anywhere, with no open ports:** install [Tailscale](https://tailscale.com)
  on the phone and the server, and use the server's Tailscale address.
- **A public address:** put it behind Caddy, which gets an HTTPS certificate
  automatically, or a Cloudflare Tunnel. Set the public URL (on the admin
  page or with `TAKO_PUBLIC_URL`) and `TAKO_TRUST_PROXY=1`, so sign-in limits
  count each client rather than the proxy.

Use HTTPS for anything outside your own network: tokens are sent with every
request. Host the Den at the root of its address (`https://den.example.com`,
not `https://example.com/den`).

## Administration

Everything is on the web page under **Admin**:

- **Server:** name, public URL, registration (closed, invite, open), whether
  people may sign in with a password (administrators always may), the
  defaults for new users, and whether users' own providers may reach
  addresses on your network.
- **Users:** add, disable or delete people; make administrators; reset
  passwords; override a user's permissions: shared models, own providers and
  the daily token limit.
- **Model providers:** shared providers, with an allowlist of models (empty
  offers everything the upstream lists) and who may use them.
- **Sign-in methods:** add Google, Discord, GitHub or OpenID Connect. Each
  shows the redirect URI to paste into the provider's OAuth settings; OAuth
  needs the public URL. Accounts are matched by the provider's account id,
  never merged by email; people link more sign-in methods in their settings.
- **Invites** with a number of uses and an expiry, sent as a link.
- **Usage** per user, model and day.

## Configure

Settings on the admin page are stored in the database. Environment variables
cover the rest; for more, copy
[tako-den.example.yaml](tako-den.example.yaml) to `tako-den.yaml`.

| Variable | Default | |
| --- | --- | --- |
| `TAKO_PORT` / `TAKO_HOST` | `8787` / `0.0.0.0` | |
| `TAKO_DATA` | `data` | Database and secret key. Back this up. |
| `TAKO_ADMIN_PASSWORD`, `TAKO_ADMIN_USERNAME` | / `admin` | Create the administrator at start-up instead of the setup link. |
| `TAKO_PUBLIC_URL` | | The public address; locks the admin page's setting. |
| `TAKO_REGISTRATION` | `closed` | The first value of the setting: `closed`, `invite` or `open`. |
| `TAKO_TRUST_PROXY` | off | Behind one reverse proxy you run: take the client address from `X-Forwarded-For`. |
| `TAKO_SECRET_KEY` | `data/secret.key` | Base64 of 32 bytes. Encrypts stored API keys and OAuth secrets. |
| `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `OLLAMA_URL` | | Add that shared provider. |
| `TAKO_OAUTH_GOOGLE_CLIENT_ID`, `…_CLIENT_SECRET` | | Add a sign-in method; likewise `DISCORD` and `GITHUB`. |
| `TAKO_OAUTH_OIDC_ISSUER`, `…_CLIENT_ID`, `…_CLIENT_SECRET`, `…_NAME` | | An OpenID Connect sign-in method. |

Providers and sign-in methods from the configuration are listed on the admin
page but edited only in the configuration.

Commands:

```sh
tako-den user add <name> [--admin]   # password from TAKO_PASSWORD or a prompt
tako-den user passwd <name>
tako-den backup <file>               # a consistent copy of the database
```

A backup of the database alone cannot decrypt stored API keys and OAuth
secrets: keep `data/secret.key` (or `TAKO_SECRET_KEY`) with it.

## API

[API.md](API.md) describes every route: sign-in (password, device sign-in,
pairing, OAuth), the account, providers, the OpenAI-compatible gateway, sync,
live events and administration.

## Security

- Passwords are stored as PBKDF2-SHA256; tokens, codes and invites only as
  hashes. Sign-in, registration, pairing and device sign-in are rate limited.
- Provider API keys and OAuth client secrets are encrypted at rest
  (AES-256-GCM) and never returned by the API or sent to clients.
- OAuth uses state bound to the browser, PKCE, and for OpenID Connect a nonce
  and a verified ID token.
- Users' own providers cannot reach loopback or private addresses unless the
  administrator allows it; the check is made on the address actually
  connected to.
- Request bodies are capped: 64 KB for sign-in, 16 MB for sync, 32 MB for
  chat and 64 MB per file.
- The web page loads nothing from other servers and runs under a strict
  Content Security Policy.
- The server can read what it stores. Run it on a machine you trust.

## Develop

```sh
dart test
dart analyze
dart format lib bin test tool
```

The web app is plain JavaScript modules in `web/`, embedded into the server
at build time. After changing it, run `dart run tool/embed_web.dart` (a test
fails while the embedded copy is stale), or serve the folder directly with
`TAKO_WEB_DIR=web`. `tool/web_check.mjs` drives every page in headless
Chrome against a fresh server; see its header.

## License

AGPL-3.0, like the app. If you offer a modified server to others, you must
offer them its source.
