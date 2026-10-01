# Codex Browser Connector Patch

A local compatibility patch for the macOS Codex / ChatGPT desktop application.
It keeps the built-in browser usable when Codex runs with API-key auth or a
third-party model provider instead of a ChatGPT account.

> This is not an OpenAI project and is not supported by OpenAI. It modifies
> files inside the installed application, bypasses local OpenAI-account checks,
> and invalidates the vendor code signature. Review the risks and applicable
> terms before using it.

## Applicable Version

The current live-verified build is:

```text
Codex Desktop / ChatGPT.app
CFBundleShortVersionString: 26.928.31416
```

This repository follows rolling application updates. The patch and recovery
scripts are intentionally current-version only:

- every `--apply` refreshes the rollback snapshot from the currently installed
  pristine App;
- old App-version backups are not retained or reused;
- if a future update changes a minified anchor, the script fails closed instead
  of guessing;
- after an update, re-run `--check` and rebuild the recipes if a target reports
  `unknown` or an unexpected match count.

## What It Fixes

The browser path has five practical gates:

| Gate | Failure | Current fix |
| --- | --- | --- |
| 1 | `Codex auth token is unavailable` | A local shim proxies the Codex app-server and rewrites only the unauthenticated `getAuthStatus` response. |
| 2 | `User unavailable` | The `chatgpt.com/backend-api/aura/identity` lookup is replaced with a local synthetic user. |
| 3 | `Unable to load browser request-header policy` | The Statsig request-header gate is disabled locally. |
| 4 | `The admin-enforced policy could not be verified` | The remote enterprise origin-policy call is replaced with a local `null` decision. Persisted per-origin user permissions still apply. |
| 5 | `No ChatGPT browser route is available for browser session ...` | Route v3 adopts a live `client-new-thread:` route owned by the asking browser backend, moves the backend key to the real conversation, rekeys the route, and rechecks it. |

Gate 5 is the important change in this revision. The older patch only relaxed
`canServeSession()` or attempted to rekey an existing placeholder; the current
implementation adopts the route before the backend-state check runs.

## Why Re-Signing Is Required

`Resources/app.asar` is protected by three integrity guards:

1. the edited entry hash in the ASAR JSON header;
2. the ASAR header SHA-256 in `Info.plist -> ElectronAsarIntegrity`;
3. the digest of that dictionary in the Codex Framework `__asar_integrity`
   Mach-O section.

Updating guard 3 invalidates the framework signature, so the patch must be
followed by an ad-hoc re-sign. The signing step drops restricted entitlements:

- push notifications;
- app-group sharing;
- keychain-group sharing.

The vendor signature cannot be restored from a backup. Reinstalling the
application is the only way back to the original signature. TCC permissions
tied to the old signature may need to be granted again.

## Requirements

- macOS
- `/Applications/ChatGPT.app` by default
- `/usr/bin/python3`
- permission to write inside the application bundle when applying the host
  patch

For the host patch, use **Terminal.app**. An agent running inside ChatGPT cannot
patch the App and restart it without terminating its own host process.

## Install and Deploy

```sh
git clone https://github.com/zjlww/codex-browser-connector-patch.git
cd codex-browser-connector-patch
bash scripts/deploy.sh
```

The scripts are copied to:

```text
~/.local/share/codex-rollback/
```

## Apply

Use the full apply path:

```sh
bash ~/.local/share/codex-rollback/apply-host-route.sh
```

This command:

1. stops the App;
2. refreshes the current-version vendor rollback point;
3. patches gates 1-4;
4. patches the route v3 host code;
5. updates all three ASAR/framework integrity hashes;
6. re-signs the App ad-hoc;
7. relaunches and verifies that the App stays up;
8. automatically restores the host files if startup fails.

Do not apply only `patch-browser-connector.py --apply` to the live App: the
host patch needs the follow-up re-sign performed by `apply-host-route.sh`.

## Check

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
```

Expected current state:

```text
app version: 26.928.31416
patched ...
patched ... app.asar
```

The check fails when a target is `unpatched`, `partial`, `unknown`,
`integrity-broken`, `header-integrity-broken`, or
`dictionary-digest-stale`.

## Verify Browser Use

In a Codex task:

```js
await cua.getState()
const tab = await cua.createBrowserTab("iab", "https://example.com")
await cua.listTabs({ browser: "iab" })
await tab.getAXState()
```

The expected result is that the in-app browser appears in inventory, the tab
binds successfully, and the page state is readable. If binding fails, inspect
the desktop log for `IAB_ROUTE_DIAG`; it lists the current route keys.

## Restore

Restore only the host files:

```sh
bash ~/.local/share/codex-rollback/restore-host-asar.sh
```

Restore every patched file:

```sh
bash ~/.local/share/codex-rollback/restore-appbundle.sh
```

Last-resort signature recovery:

```sh
bash ~/.local/share/codex-rollback/recover-code-signature.sh
```

The rollback data is under:

```text
~/.local/share/codex-rollback/appbundle-orig/
```

It contains the current-version vendor files only.

## Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `CHATGPT_APP` | `/Applications/ChatGPT.app` | App bundle path |
| `CODEX_BROWSER_ROLLBACK_DIR` | `~/.local/share/codex-rollback` | Helper and backup directory |
| `CODEX_AUTH_SHIM_REAL_CLI` | auto-detected | Explicit Codex CLI path for the shim |

## Security Boundaries

- No ChatGPT credentials, passwords, cookies, API keys, or account tokens are
  stored in this repository.
- `codex-auth-shim.py` creates a synthetic local token only to satisfy the
  node-runtime gate.
- Gate 4 replaces the remote enterprise-policy source with a local decision;
  this is an intentional compatibility tradeoff.
- Gate 5 modifies the closed Electron host and invalidates the signature.
- Every application update can overwrite the patched files. Re-run `--check`
  and `apply-host-route.sh` after an update.

## Update Workflow

After a ChatGPT/Codex update:

```sh
defaults read /Applications/ChatGPT.app/Contents/Info CFBundleShortVersionString
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
```

If the App is pristine and the anchors still match:

```sh
bash ~/.local/share/codex-rollback/apply-host-route.sh
```

If the script reports `unknown` or an unexpected regex match count, extract the
changed minified function from the new `app.asar` or `browser-service.mjs`,
update the matching recipe in `scripts/patch-browser-connector.py`, validate on
a copy, and publish the new revision.
