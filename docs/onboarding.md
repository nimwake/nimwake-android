# Onboarding — host your own apps on an Android phone

[한국어](onboarding.ko.md)

This guide takes you from an empty folder to your own site running on a phone, reachable from the internet. It covers the **consumer repo**: your own (usually private) repository that holds your apps and domain, and uses nimwake-android to put them on the phone.

> Keep this guide in sync: `onboarding.md` (English, default) and `onboarding.ko.md` (Korean) must have the same headings and the same code blocks — `make lint` checks it, along with every `make` target the code blocks use.

## How the pieces fit

```text
your consumer repo      apps/<name>/ (source + nimwake.toml) · domain · token file path (.env)
  └── nimwake-android   pinned by nimwake-android.lock — install, supervisor, deploy-app, ingress
        └── phone        Termux → proot Ubuntu → nimwaked (Core) → your apps, woken on demand
              └── Cloudflare Tunnel (optional) → https://<your name>
```

- **nimwake-android** (this repo) runs the phone: installing, booting, watching, deploying, and exposing apps.
- **Your consumer repo** only has your apps and your domain. It never contains secrets — `.env` holds a *path* to the token file.
- **Core** (`nimwaked`) routes each request by its `Host` header to the app whose manifest names that host, starts it on the first request, and stops it when idle.

## What you need

| | |
| - | - |
| Phone | Android with Termux, Termux:Boot, Termux:API from the **same source** (F-Droid). Prepared with `make install` — see the [README](../README.md#기기-준비) |
| Dev machine | macOS or Windows + WSL2 (Ubuntu). `git`, `make`, `ssh`, `curl`, and Node at the version in [`guest/node.lock`](../guest/node.lock) (for example via `mise`) |
| Domain | Optional. Without one you can still get a public URL (quick tunnel, step 5) |

## 1. Prepare the phone

Once, from a checkout of nimwake-android:

```sh
make install          # packages, proot Ubuntu, key-only sshd, Core, supervisor, doctor
make doctor           # [OK]/[WARN]/[FAIL] for the phone
make backup           # keep host.conf and soak records on this machine
```

The README's device section lists the few manual steps before ssh works (install the apps, start `sshd`, register your key).

## 2. Create your consumer repo

Copy the template, then pin the nimwake-android version you deploy with:

```sh
cp -R nimwake-android/examples/consumer-template my-sites
cd my-sites
git init
cp .env.example .env  # NIMWAKE_DEVICE, CLOUDFLARE_TOKEN_FILE — never commit .env
```

`nimwake-android.lock` decides which nimwake-android your repo uses:

```text
repo=nimwake/nimwake-android
rev=v0.1.0
```

- `rev` is a **release tag or a commit SHA** — never `main`, which moves under you.
- Choose a tag from the [releases](https://github.com/nimwake/nimwake-android/releases) and check the [CHANGELOG](../CHANGELOG.md). Some features need a newer version than the template pins — see [Version notes](#version-notes).

Then fetch that version into `.nimwake-android/` (ignored by git):

```sh
make setup
```

## 3. Add an app

Each app is a folder under `apps/`:

```text
apps/<name>/
  nimwake.toml   Core manifest — name, host, port, command, lifecycle
  exposure       public | lan (missing means lan)
  app/           your project's source (package.json + package-lock.json)
  bundle/        build output — created by make deploy, ignored by git
```

Pick the example that matches your app and copy it:

| Your app | Copy | `command` | Notes |
| -------- | ---- | --------- | ----- |
| Static site — Vite, Vite + TanStack Router / React Router, Docusaurus | `apps/site` | `server.mjs` | `SPA = "1"` for client routers, `"0"` for sites with a page per URL (Docusaurus) |
| Next.js | `apps/blog` | `server.js` | `output: "standalone"` and `images.unoptimized: true` in `next.config.mjs` |

```sh
cp -R apps/site apps/about
```

Then edit `apps/about/nimwake.toml`:

| Field | Set it to |
| ----- | --------- |
| `name` | the folder name — lowercase letters, digits, `-` |
| `[server] host` | the public hostname, exactly as visitors type it (and as registered in Cloudflare) |
| `[server] port` and `PORT` | a port no other app uses, 1024–65535, not 8080 |
| `[server] allow` | only for LAN-only apps: `["192.168.0.0/16"]` (your LAN, on one line) |
| `working_dir` | **leave it out** — deploy fills it in |

And `apps/about/exposure`: `public` to publish it through the tunnel, `lan` to keep it at home.

Rules the deploy checks for you (`make deploy` refuses or warns before touching the phone):

- the build runs **on your machine**, never on the phone, and must not contain native modules (`*.node`);
- the only runtime is the Node from `guest/node.lock` (`/opt/node/bin/node`);
- a `public` app must not have an `allow` that leaves out `127.0.0.1` — tunnel traffic comes from there;
- `VITE_*` and other build-time values end up in the browser — never put secrets there.

## 4. Deploy and check it on your LAN

```sh
make deploy APP=about    # build → bundle/ → phone → reload; other apps keep running
make status              # apps, Core, supervisor, ingress
```

To reach apps from other devices at home, open the phone's gateway to the LAN once (the default is loopback only), then restart:

```sh
ssh nimwake-phone 'echo NIMWAKE_LISTEN=0.0.0.0:8080 >> ~/.nimwake-host/host.conf'
make restart
curl -H 'Host: about.example.com' http://<phone IP>:8080/
```

The first request after the app has been idle is a **cold start** (about 1 s for a static site, 1.6 s for Next.js on the reference phone); after that it is tens of milliseconds.

## 5. Go public

### Without a domain — quick tunnel

```sh
make ingress MODE=quick
make restart
make status              # ingress cloudflare RUNNING — connected https://<random>.trycloudflare.com
```

No account or token. The URL changes every time the tunnel restarts, and it serves **one** public app (the first `public` one, or `NIMWAKE_INGRESS_CF_QUICK_HOST` in the phone's `host.conf`). Good for trying things, not for keeping.

### With your domain — token mode

1. Add the domain to Cloudflare (buying it at Cloudflare Registrar skips the nameserver step).
2. Zero Trust → Networks → Tunnels → **Create a tunnel** (Cloudflared). Save the token to a file **outside** the repo and `chmod 600` it; put that path in `.env` as `CLOUDFLARE_TOKEN_FILE`.
3. Add a **Public Hostname** for each public app — `about.example.com` → `HTTP` `localhost:8080`. One name per app; no wildcards.
4. On the phone:

```sh
make ingress
make token               # reads the token file through stdin, stores it 0600 on the phone
make restart
make status
```

Several domains can share one tunnel and one phone — add each as a Public Hostname and give each app its own `host`.

## 6. Day to day

```sh
make deploy APP=about    # ship a new release (the phone keeps the last three)
make rollback APP=about  # back to the previous release
make status
```

Upgrade nimwake-android: change `rev` in `nimwake-android.lock` to the new tag and read its CHANGELOG, then update both this machine and the phone:

```sh
make setup                                   # fetch the new nimwake-android into .nimwake-android/
make -C .nimwake-android fetch-core deploy   # put its Core and Host Layer on the phone
make restart                                 # run them (apps start again on the next request)
make deploy APP=about                        # rebuild your app with the new build tools
```

## Troubleshooting

| You see | Do this |
| ------- | ------- |
| `make deploy` stops: `native module` | a dependency ships a compiled `.node` file — drop it or use a pure-JS alternative |
| `app-manifest: … does not include 127.0.0.1` | a `public` app with `allow` — remove `allow`, or add `"127.0.0.1/32"` |
| `app-manifest: warning: … lan but has no [server] allow` | add `allow = ["192.168.0.0/16"]` so the tunnel can never reach it |
| `core: … keeping the current set` | Core rejected the manifest (duplicate port, bad CIDR …); deploy restored the previous one — read the message |
| `/about` is 404 on a static site, `/` works | set `SPA = "1"` for client-side routers |
| 503 from the gateway | the phone is short on memory (`NIMWAKE_MIN_FREE_MEMORY_MB`) — fewer awake apps, or a lower threshold |
| `ssh: connect … refused` after days of uptime | Android stopped Termux. Open Termux, run `sshd`, then `nimwake-host start` |
| Quick tunnel URL stopped working | it changes on every restart — read the new one from `make status` |

## Version notes

| Feature | nimwake-android | Core |
| ------- | --------------- | ---- |
| Next.js apps, `make deploy`, Cloudflare ingress, `exposure` | v0.1.0 | v0.1.0 |
| `[server] allow` (403 for other peers, does not wake the app) | v0.1.0 | v0.1.0 |
| Static sites (`server.mjs`, `SPA`) | after v0.1.0 — commit `8cce97b` until the next tag | v0.1.0 |
| `nimwake status` on the phone (Core control socket) | after v0.1.0 | v0.1.2 or later — use v0.1.4 |

## Reference

- [Consumer template README](../examples/consumer-template/README.md) — the template itself (Korean)
- [Deploy and ingress contract](../.docs/phases/phase-2/03-deploy-and-ingress-contract.md) · [Exposure security](../.docs/phases/phase-2/04-exposure-security.md) (Korean)
- [CHANGELOG](../CHANGELOG.md) · [Validation reports](../.docs/validation/)
