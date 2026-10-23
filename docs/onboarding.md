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
rev=v0.1.1
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

**Data your app keeps** (SQLite, uploads, caches) goes in the directory named by the `NIMWAKE_DATA_DIR` environment variable — `/home/nimwake/data/<name>` on the phone. The deploy creates it and fills the variable in; don't set it yourself. The working directory is a new release folder on every deploy, so anything written there is gone after the next one. The data directory survives redeploys, rollbacks and `remove-app`, and `make backup` copies it to your machine (`make restore-data` puts it back on a wiped phone).

## 4. Deploy and check it on your LAN

```sh
make deploy APP=about    # build → bundle/ → phone → reload; other apps keep running
make status              # apps, Core, supervisor, ingress
```

After the reload, `make deploy` **wakes the new release once**. If it does not start (Core reports `FAILED`, no answer, or a 5xx from the gateway), the deploy puts the previous release back, prints the app's last log lines, and fails — your site keeps serving the old version. A brand-new app that never starts is removed again. Set `NO_VERIFY=1` to skip the check. An app whose `allow` leaves out `127.0.0.1` cannot be woken from the phone itself; the deploy says so and keeps it.

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

## 7. Scheduled jobs and webhooks

Nimwake has no scheduler, and an app that is asleep cannot run its own cron. **Wake it from outside with an HTTP request** — the request starts the app, the app does the work, and it goes back to sleep.

| Need | Use |
| ---- | --- |
| Run something every night / every 10 minutes | GitHub Actions `schedule`, or a Cloudflare Worker with a Cron Trigger, calling an endpoint of your app |
| React to an event (GitHub push, payment, form) | the service's webhook, pointed at your app |
| Work that must not be lost while the phone is off | a queue outside the phone (Cloudflare Queues) whose consumer calls your app and retries |

From GitHub Actions:

```yaml
# .github/workflows/nightly.yml in your consumer repo
on:
  schedule:
    - cron: "0 15 * * *"   # UTC — 00:00 KST. GitHub may start it minutes late
  workflow_dispatch: {}
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - run: |
          curl -fsS -m 120 -X POST https://jobs.example.com/run/nightly \
            -H "CF-Access-Client-Id: ${{ secrets.CF_ACCESS_CLIENT_ID }}" \
            -H "CF-Access-Client-Secret: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}"
```

From a Cloudflare Worker:

```js
// Cloudflare Worker with a Cron Trigger (wrangler.toml: [triggers] crons = ["*/10 * * * *"])
export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(fetch("https://jobs.example.com/run/check", {
      method: "POST",
      headers: {
        "CF-Access-Client-Id": env.CF_ACCESS_CLIENT_ID,
        "CF-Access-Client-Secret": env.CF_ACCESS_CLIENT_SECRET,
      },
    }));
  },
};
```

Rules that keep this reliable on a phone:

- **Put a Cloudflare Access application with a service token in front of the job hostname** (`jobs.example.com`). Only callers with the token get through, so the app itself needs no auth code. Store the token as a GitHub secret or a Worker secret.
- **Do the work inside the request** and answer when it is done. Nimwake stops an app `idle_timeout_seconds` after its last request — work left running after the response can be cut off. Raise `response_header_timeout_seconds` for jobs longer than a minute, or split them.
- **Make jobs idempotent.** A scheduled call can arrive late, twice, or not at all (phone off, home internet down). Keep what was done in `NIMWAKE_DATA_DIR` and skip work that is already done.
- **Webhooks:** verify the sender's signature (for GitHub, `X-Hub-Signature-256`). A cold start (1–2 s) fits inside GitHub's 10 s limit. A webhook sent while the phone is off is not retried automatically — redeliver it from the sender's page.
- **Secrets the app reads** (webhook secrets, API keys) go in a file in the app's data directory on the phone, not in `nimwake.toml`, which lives in your repo:

```sh
# a secret the app reads at runtime — on the phone, never in the repo or the manifest
ssh nimwake-phone 'umask 077; cat > "$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/data/jobs/webhook-secret"' < ~/.secrets/jobs-webhook-secret
```

## Troubleshooting

| You see | Do this |
| ------- | ------- |
| `make deploy` stops: `native module` | a dependency ships a compiled `.node` file — drop it or use a pure-JS alternative |
| `app-manifest: … does not include 127.0.0.1` | a `public` app with `allow` — remove `allow`, or add `"127.0.0.1/32"` |
| `app-manifest: warning: … lan but has no [server] allow` | add `allow = ["192.168.0.0/16"]` so the tunnel can never reach it |
| `apps: release … did not start (…) — rolling back` | the new release crashed on start; the log lines below the message show why. The previous release is serving again |
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
| Static sites (`server.mjs`, `SPA`) | v0.1.1 | v0.1.0 |
| `NIMWAKE_DATA_DIR` (persistent app data), `make restore-data` | v0.1.1 | v0.1.0 |
| `nimwake status` on the phone (Core control socket) | v0.1.1 | v0.1.2 or later — v0.1.1 pins v0.1.4 |

## Reference

- [Consumer template README](../examples/consumer-template/README.md) — the template itself (Korean)
- [Deploy and ingress contract](../.docs/phases/phase-2/03-deploy-and-ingress-contract.md) · [Exposure security](../.docs/phases/phase-2/04-exposure-security.md) (Korean)
- [CHANGELOG](../CHANGELOG.md) · [Validation reports](../.docs/validation/)
