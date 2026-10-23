# Contract — what nimwake-android promises

[한국어](contract.ko.md) · [Onboarding](onboarding.md)

This page lists everything a consumer repo or an operator may rely on. **From v1.0.0 these follow SemVer:** changing or removing any of them needs a major version; a minor version may add to them. Something about to go away stays for at least one minor version with a warning first. Anything not listed here — log wording, human-readable `status` lines, files under `~/.nimwake-host/run/`, test output — may change in any release.

> `make lint` checks that every key in `host/host.conf.example` appears on this page, and that every `make` target in its code blocks exists.

## Versions

| | |
| - | - |
| A consumer repo pins | `nimwake-android.lock` → `rev=<release tag or commit SHA>`, never `main` |
| This repo pins Core | `core.lock` → a Core release tag and its commit; `make fetch-core` checks the commit |
| Node for apps | `guest/node.lock` — version and sha256; installed on the phone as `/opt/node/bin/node` |

## App directory

```text
apps/<name>/
  nimwake.toml   Core manifest
  exposure       public | lan  (missing means lan)
  app/           source, built on your machine (package.json + package-lock.json)
  bundle/        what runs on the phone — produced by the build, never built on the phone
```

Manifest rules the deploy enforces before touching the phone:

| Rule | |
| ---- | - |
| `name` | lowercase letters, digits, `-` — it becomes a path on the phone |
| `[server] host` | the public hostname; one host per app |
| `[server] port` | 1024–65535, not 8080, unique on the phone |
| `[server] allow` | one line. A `public` app must include `127.0.0.1` or leave `allow` out; a `lan` app without it gets a warning |
| `[runtime] command` | `/opt/node/bin/node` or a binary under `/opt/nimwake/bin/` |
| `working_dir`, `NIMWAKE_DATA_DIR` | never set them — the deploy fills both |
| bundle | no native modules (`*.node`) |

What the app is given:

| | |
| - | - |
| Working directory | the release directory — **replaced on every deploy** |
| `NIMWAKE_DATA_DIR` | `/home/nimwake/data/<name>` (0700) — survives redeploy, rollback and `remove-app`; copied by `make backup` |
| Network | it listens on `127.0.0.1:<port>`; requests arrive through the gateway with `X-Forwarded-For` (the rightmost value is the peer the gateway saw) |

## Deploy semantics

| Command | Promise |
| ------- | ------- |
| `deploy-app` | the bundle becomes a new release; Core reloads without touching other apps; the new release is woken once and **rolled back if it does not start** (`NO_VERIFY=1` skips that); the last three releases are kept |
| `rollback-app` | back to the previous release |
| `remove-app` | the app stops and leaves routing; its releases and data stay on the phone |
| `exposure` | only `public` apps are handed to the ingress |

## Commands

This repo:

```sh
make install                      # set up a phone (idempotent)
make deploy                       # Core and Host Layer onto the phone
make restart                      # restart the supervisor (reads host.conf)
make deploy-app APP=<dir>         # deploy one app directory
make rollback-app NAME=<name>
make remove-app NAME=<name>
make apps                         # apps, host, port, exposure, release, state
make logs APP=<name>              # LINES=, FOLLOW=1
make ingress-enable INGRESS=cloudflare
make ingress-token INGRESS=cloudflare
make ingress-disable
make backup                       # host.conf, soak records, app data → ~/.nimwake-backup/<device>
make restore-data
make doctor
make device-status
make verify                       # every check that needs no hands
```

Consumer template:

```sh
make setup
make deploy APP=<name>
make rollback APP=<name>
make ingress
make token
make restart
make status
make logs APP=<name>
make verify
make upgrade REV=<tag>
```

On the phone: `nimwake-host start | stop | status | logs [N]`, and `nimwake` — the Core CLI with the control socket already set (`nimwake status`, `nimwake status --json`; the JSON is Core's contract and carries its own `contract` number).

## `host.conf`

`~/.nimwake-host/host.conf` on the phone, `KEY=value`. A missing key takes its default. `make deploy` never overwrites the file; `make backup` keeps a copy.

| Key | Meaning |
| --- | ------- |
| `NIMWAKE_LISTEN` | gateway address. Empty = Core's default `127.0.0.1:8080`; `0.0.0.0:8080` opens it to the LAN |
| `NIMWAKE_CONTROL_SOCKET` | `1` (default) runs Core with its control socket |
| `NIMWAKE_ISOLATED` | `1` (default) runs Core and apps in an isolated proot |
| `NIMWAKE_MIN_FREE_MEMORY_MB` | Core's memory admission and idle eviction threshold. Empty = off |
| `NIMWAKE_HEALTH_INTERVAL` · `NIMWAKE_HEALTH_FAILURES` | how often the supervisor probes Core, and after how many failures it restarts it |
| `NIMWAKE_MAX_RESTARTS` · `NIMWAKE_RESTART_WINDOW` | crash-loop limit — that many restarts within the window means `UNHEALTHY` |
| `NIMWAKE_HOUSEKEEPING_INTERVAL` | seconds between storage, battery and log-rotation checks |
| `NIMWAKE_MIN_FREE_MB` · `NIMWAKE_STORAGE_CLEANUP` | low-storage alert threshold, and whether rotated logs are removed first |
| `NIMWAKE_NOTIFY` | alert command; message in `$1`, kind (`storage`, `battery`) in `$2` |
| `NIMWAKE_BATTERY_WATCH` · `NIMWAKE_BATTERY_LOW` | battery watch on/off, and the low-battery percentage |
| `NIMWAKE_LOG_MAX_KB` · `NIMWAKE_LOG_KEEP` | log rotation size and how many old logs to keep |
| `NIMWAKE_NET_INTERVAL` · `NIMWAKE_NET_GATEWAY` · `NIMWAKE_NET_INTERNET_URL` | network watch interval, router to probe, optional internet probe |
| `NIMWAKE_NET_ON_RECOVER` · `NIMWAKE_NET_HOOK_TIMEOUT` | command run when the network comes back, and its time limit |
| `NIMWAKE_INGRESS` | ingress provider (`cloudflare`), empty = none |
| `NIMWAKE_INGRESS_CF_MODE` · `NIMWAKE_INGRESS_CF_QUICK_HOST` · `NIMWAKE_INGRESS_CF_METRICS` | cloudflare provider: `token` or `quick`, the host quick mode serves, the metrics address |

## Ingress provider

`host/ingress/<provider>/` holds four executables:

| File | Contract |
| ---- | -------- |
| `check` | exit 0 when everything the provider needs is present; otherwise one line saying what is missing |
| `install` | install what it needs; idempotent |
| `run` | run in the foreground. The supervisor restarts it when it exits; exit `78` means a configuration error and is not restarted |
| `health` | exit 0 when connected; may print one line (for example the public URL) |

They receive `NIMWAKE_GATEWAY` (where to send traffic), `NIMWAKE_INGRESS_HOSTS` (the hostnames of `public` apps, space-separated), `NIMWAKE_SECRETS` (a 0700 directory for tokens), `NIMWAKE_LOGS`, and every `NIMWAKE_INGRESS_*` key from `host.conf`. The provider forwards those hostnames to the gateway; in cloudflare's `token` mode the `Host` header is unchanged, in `quick` mode it is set to one app's host (`NIMWAKE_INGRESS_CF_QUICK_HOST`, or the first public app).
