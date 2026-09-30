# Codex Browser Connector Patch

A local compatibility patch for the macOS Codex / ChatGPT desktop app. It
restores the built-in browser and Chrome connector when Codex uses API-key
authentication or a custom model endpoint without a ChatGPT account session.

> This is not an OpenAI project and is not supported by OpenAI. It modifies
> files inside the installed application and bypasses authentication,
> request-header, enterprise-policy, and CDP gates. It invalidates the app code
> signature and may violate the applicable terms of service. Use it only for
> local compatibility work after understanding the risks.

## Applicable Version

The fully verified version is:

```text
Codex Desktop / ChatGPT.app
CFBundleShortVersionString: 26.928.21956
```

Version notes:

- `26.928.21956`: verified, including in-app browser navigation, native Codex
  computer use, and a raw CDP `Runtime.evaluate` call.
- Older versions: the scripts retain legacy patch markers, but this public
  release was not revalidated against older application builds.
- Newer or unknown versions: support is not guaranteed. Codex updates commonly
  rename minified functions, move executables, and add fail-closed checks.
- If `--check` reports `unknown`, `partial`, or an unexpected regex match count,
  update the matching rules instead of forcing the patch.

> **Important:** Run the patch check after every Codex update. If the update
> breaks the patch or creates a new browser gate, update this repository before
> continuing. A surviving old marker does not prove that the patch is still
> effective.

### Suggested Update Workflow

1. Check the installed version:

   ```sh
   defaults read /Applications/ChatGPT.app/Contents/Info CFBundleShortVersionString
   ```

2. Check the patch:

   ```sh
   python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
   ```

3. If any target is not `patched`, open an issue or pull request and include:
   - the Codex version;
   - the complete error message;
   - the `--check` output;
   - the changed error string or function fragment from the new
     `browser-service.mjs`.

4. Update the matching rules, re-run the verification, and publish the new
   revision only after CDP and navigation work again.

## Supported Environment

- macOS
- `/Applications/ChatGPT.app`
- Apple's `/usr/bin/python3`
- No root access is required by default, but the current user must be able to
  write to the application bundle.

## Background and Root Causes

The browser runtime can fail at five layers. Gates 1–4 are app/browser-service
gates; the fifth is the Electron host's browser-session route:

| Gate | Common error | Patch behavior |
| --- | --- | --- |
| Authentication | `Codex auth token is unavailable` | A local shim proxies the Codex app-server and rewrites only the unauthenticated `getAuthStatus` response. |
| Identity lookup | `User unavailable` | The `aura/identity` lookup is replaced with a local synthetic user. |
| Request-header policy | `Unable to load browser request-header policy` | The Statsig-backed request-header gate returns `false` locally. |
| Enterprise origin policy | `The admin-enforced policy could not be verified` | `getOriginPolicyDecision()` returns a local `null` result instead of querying the remote enterprise-policy source. |
| Browser session route | `No ChatGPT browser route is available for browser session ...` | The Electron host must register an IAB route and connect the native browser pipe; on `26.928.21956`, this recovered once the shim could start the real Codex CLI. |

These gates assume a signed-in ChatGPT account and access to remote identity,
Statsig, and enterprise-policy services. In API-key or custom-provider mode, any
failed check can terminate the browser flow by design.

The original compatibility patch handled only:

- `getAuthStatus` returning no authentication token;
- `chatgpt.com/backend-api/aura/identity` returning `User unavailable`.

Codex `26.928.21956` added the Statsig request-header policy and enterprise
origin-policy checks. The old patch could therefore still report success while
navigation failed. The current script also reports `partial`, so an old partial
patch is not mistaken for a complete one.

CDP also depends on the authentication shim successfully starting the real
Codex CLI. In `26.928.21956`, the CLI moved from:

```text
Contents/Resources/codex
```

to:

```text
Contents/Resources/codex-cli/bin/codex
```

The old shim therefore exited immediately. Basic browser navigation could still
work through other local patches, but `configRequirements/read` could not
complete. `fullCdpAccessState()` then failed closed and the tab did not expose
the `cdp` capability.

The missing CLI also left the Electron host without a healthy app-server route.
The host logged:

```text
No ChatGPT browser route is available for browser session <session-id>
```

After the shim was repaired, the same host logged:

```text
captured session route conversationId=<session-id>
browser-use native pipe listening pipePath=/tmp/codex-browser-use/<id>.sock
browser_use_iab_backend_startup_ready backend=iab
```

This is why repairing only gates 1–4 can still leave IAB incomplete. The
browser-service may advertise an IAB backend, but the Electron host must also
register the route and native pipe for the current conversation.

## What the Patch Does

### 1. Replaces the `node_repl` Entry Point

The original binary is preserved as:

```text
/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl-vendor
```

The new `node_repl` is a small shell wrapper. It sets `CODEX_CLI_PATH` only for
the Codex node runtime and points it at the local `codex-auth-shim.py`. The
application's own app-server continues to use the real Codex CLI.

### 2. Rewrites the Local Authentication State in the Shim

`codex-auth-shim.py` starts the real Codex CLI and forwards its JSON-RPC
messages. The only modified response is the unauthenticated `getAuthStatus`
result, which is replaced with a local synthetic `chatgpt` token.

The token is used only to pass the local node-runtime check. The repository does
not contain account credentials, passwords, cookies, or user data.

The shim searches for the real CLI in this order:

1. `CHATGPT_APP/Contents/Resources/codex`
2. `CHATGPT_APP/Contents/Resources/codex-cli/bin/codex`
3. `CHATGPT_APP/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`

An explicit path can also be supplied:

```sh
export CODEX_AUTH_SHIM_REAL_CLI="/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
```

### 3. Patches the Browser Service Gates

`patch-browser-connector.py` modifies the application-bundle and plugin-cache
copies of `browser-service.mjs`:

1. `getAuthStatus` is handled by the wrapper and shim.
2. The `aura/identity` lookup is replaced with a synthetic user.
3. The Statsig request-header gate returns `false`.
4. `getOriginPolicyDecision()` returns a local `null` result.

Every original file is backed up under `appbundle-orig/`. Markers allow
`--check` to distinguish complete, partial, and unknown patch states.

## Security Boundaries

- The scripts do not write ChatGPT usernames, passwords, cookies, or API keys.
- `codex-auth-shim.py` generates a synthetic token locally for the internal
  application check.
- Gate 4 bypasses the application's enterprise origin-policy source. Persisted
  per-origin user permissions remain a separate check.
- Modifying the application bundle invalidates its code signature.
- Every application update can overwrite the patched files. Re-run `--check` and
  `--apply` after each update.

## Why a Full Application Restart Is Required

The Codex browser service is a long-running process. After changing
`browser-service.mjs` or `node_repl` on disk, `js_reset` alone does not replace
the resident browser-service supervisor. The app must be fully stopped and
started so the new process loads the patched files.

Changing `full_cdp_access_enabled` should also be followed by a full application
restart, because the resident service may retain the value loaded at startup.

## CDP Support

When `~/.codex/browser/config.toml` contains:

```toml
full_cdp_access_enabled = true
```

the repaired shim allows browser-service to complete
`configRequirements/read` and expose the `cdp` capability on supported in-app
browser tabs.

Verification:

```js
await agent.documentation.get("capabilities/tab/cdp");
const tab = await cua.createBrowserTab("iab", "https://example.com");
const capabilities = await tab.capabilities.list();
const cdp = await tab.capabilities.get("cdp");
const result = await cdp.send("Runtime.evaluate", {
  expression: "({title: document.title, url: location.href})",
  returnByValue: true,
});
```

Expected capability list:

```text
pageAssets, webmcp, cdp
```

The CDP request should return the Example Domain title and URL.

## Usage

### 1. Clone

```sh
git clone https://github.com/zjlww/codex-browser-connector-patch.git
cd codex-browser-connector-patch
```

### 2. Deploy the Helper Scripts

```sh
bash scripts/deploy.sh
```

The default destination is:

```text
~/.local/share/codex-rollback/
```

### 3. Check the Patch State

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
```

Exit code `0` means every target is patched. `partial` means only an older or
incomplete variant is present. `unknown` means the application layout changed
and the matching rules need review.

### 4. Apply the Patch

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --apply
```

Original files are backed up under:

```text
~/.local/share/codex-rollback/appbundle-orig/
```

### 5. Fully Restart the Application

```sh
python3 -c "import subprocess;subprocess.Popen(['/bin/bash','$HOME/.local/share/codex-rollback/restart-once.sh'],start_new_session=True)"
```

### 6. Verify

In a Codex session:

```js
await cua.getState();
const tab = await cua.createBrowserTab("iab", "https://example.com");
await tab.getAXState();
```

Expected result:

- Chrome and Codex In-app Browser are listed.
- The in-app browser opens `https://example.com`.
- `getAXState()` returns the Example Domain content.

## Restore the Original Application

```sh
bash ~/.local/share/codex-rollback/restore-appbundle.sh
```

Then restart the application. The restore script:

- restores `browser-service.mjs` from `appbundle-orig/`;
- restores `node_repl-vendor` as the original `node_repl`;
- keeps the backups available for later checks.

If restoration is still incomplete, reinstall the application from the official
installer.

## Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `CHATGPT_APP` | `/Applications/ChatGPT.app` | Application bundle path |
| `CODEX_BROWSER_ROLLBACK_DIR` | `~/.local/share/codex-rollback` | Backup and helper directory |
| `CODEX_HOME` | `~/.codex` | Codex configuration and plugin cache |
| `CODEX_AUTH_SHIM_REAL_CLI` | Auto-discovered Codex CLI | Explicit real CLI path for the shim |

## Repository Layout

```text
.
├── README.md
└── scripts
    ├── codex-auth-shim.py
    ├── deploy.sh
    ├── patch-browser-connector.py
    ├── restart-once.sh
    └── restore-appbundle.sh
```

## Adapting to a New Codex Version

New Codex releases commonly:

- rename or move minified JavaScript functions;
- add new fail-closed security checks;
- move bundled executables;
- leave old patch markers in place while changing the actual execution path.

Check the patch after every update:

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
```

If the result is not fully `patched`, inspect the new
`browser-service.mjs`, `node_repl`, and Codex CLI layout. Update the paths,
markers, and regular expressions in
[`scripts/patch-browser-connector.py`](scripts/patch-browser-connector.py).

## Known Limitations

- The patch depends on minified JavaScript from a specific Codex release.
- Gate 5 is host-side route registration. If `No ChatGPT browser route` remains
  after the shim and app-server are healthy, the failure is outside the four
  browser-service gates and requires a host/session lifecycle fix.
- Only the built-in browser has been fully verified; Chrome extension navigation
  has not been separately exercised in every release.
- CDP requires full CDP to be enabled in `browser/config.toml` and requires the
  shim to find the current Codex CLI.
- Gate 4 bypasses the enterprise origin-policy source.
- Modifying the application bundle invalidates its code signature.
- Future versions may move the relevant code or add new gates.

## License

MIT
