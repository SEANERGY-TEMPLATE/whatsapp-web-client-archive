# whatsapp-web-client-archive

A scheduled archive of the WhatsApp Web entry point. Each run saves the live
`https://web.whatsapp.com/` `index.html` as `<version>.html`, so a known-good
version can be pinned when WhatsApp ships a breaking change.

## How it works

`archive-version` reuses the mechanism whatsapp-web.js already relies on:

1. Launch Puppeteer with the anti-detection flags copied from
   whatsapp-web.js's `tools/version-checker/update-version`. A plain HTTP
   request is not enough — WhatsApp answers those with HTTP 400.
2. Capture the **raw** `index.html` response body during navigation, the same
   way `Client.initWebVersionCache()` does. Note that `page.content()` would be
   wrong here: it returns the DOM after scripts have run, not what the server
   sent.
3. Read the version from `window.require('WAWebBuildConstants').VERSION_STR`
   once the module registry is up.
4. Write `<version>.html` and update `.version`. An already-archived version is
   skipped, so extra runs are harmless.

**No WhatsApp login is required.** Both the HTML body and the version string are
available on the QR screen, and the browser runs in a throwaway profile, so this
never touches an existing `.wwebjs_auth` session.

## Usage

```bash
./archive.sh                    # run an archive pass
./status.sh                     # recent runs and divergences; exit 1 if the last run failed
./compare-versions              # how much changed between each consecutive version
./compare-versions --verbose    # ...plus which bundle URLs moved
./compare-versions --json       # machine-readable
.\archive.ps1                   # Windows
```

## Measuring how much changed

Each new build is compared against the newest one already archived, and anything
that changed 30% or more is flagged in the log:

```
WARN DIVERGENCE 2.3000.1043972371 differs from 2.3000.1030000000 by 91.7% —
  bundle similarity 8.3% (+11, -11), bootloader similarity 57.9%,
  size -55757 bytes; risk high. Test whatsapp-web.js against this build
  before pinning it.
```

Comparing whole files does not work. WhatsApp stamps every response with a CSP
nonce, a request id, a `ServerNonce`, a React mount id and a request timestamp,
plus `data-content-len` fields that shift as a consequence — two fetches of the
*same* version differ by ~28 bytes across ~60 lines. Normalising all of that away
is a losing game, because a token type we have not seen yet would silently make
every run look like a change.

So `fingerprint.js` compares only what is stable and meaningful. The bundle URLs
under `static.whatsapp.net/rsrc.php` are content-addressed, so they change exactly
when the shipped code changes, and they were verified byte-identical across
independent fetches of one version. Similarity is the Jaccard index of those URL
sets — the fraction of the client that carried over — alongside the same measure
over `data-bootloader-hash` values and the `data-btmanifest` build number.

Risk is a rough read on that number, not a guarantee: `identical`, `low` at 80%+,
`moderate` at 50–80%, `high` below 50%. A build that replaced most of its bundles
is likelier to have moved the internals whatsapp-web.js reaches into.

Scheduled runs happen every two days at 12:00 UTC (21:00 KST) via
`.github/workflows/archive.yml`, which commits new versions back to this repo.

## Failure handling

WhatsApp can fail, and worse, it can succeed with the wrong thing. The archive is
only useful if a bad response never reaches it, so every run is gated:

- **Response is validated before it is written.** A healthy `index.html` is
  ~575 KB, titled `WhatsApp Web`, and references bundles many times. WhatsApp's
  error page is ~6 KB, titled `Error`, and references none. A body failing any of
  those checks aborts the run instead of being archived under a valid version
  number.
- **Existing files are re-validated on every run.** Without this, one corrupt or
  half-written file would be skipped by the already-archived check forever. A file
  that fails validation is replaced and the replacement is logged.
- **Writes are atomic** (`.tmp` then rename), so a run killed mid-write cannot
  leave a truncated file behind.
- **HTTP status and redirects are checked explicitly**, so a served error page is
  reported as `HTTP 400` rather than surfacing as an opaque timeout minutes later.
- **Timeouts at every level** — navigation, client boot, and a whole-run watchdog
  — so a wedged browser cannot hang a scheduled run indefinitely.
- **Transient failures are retried** three times with increasing backoff, because
  the next scheduled attempt is days away.
- **The version string is format-checked** before being used as a filename.

Failures exit non-zero, print a diagnostic naming the HTTP status, page title and
module-registry state, and append a record to `archive-log.jsonl`. Human-readable
output goes to `archive.log`, rotated at 1 MB.

Note that cron does not catch up missed runs, so a run skipped while the machine
was off is simply lost. Because versions are the dedupe key and WhatsApp ships
slower than every two days, the next run usually still captures it.

## Consuming an archived version

Point whatsapp-web.js at this directory and pin the version you want:

```js
const client = new Client({
    webVersion: '2.3000.1043972371',
    webVersionCache: {
        type: 'local',
        path: '../whatsapp-web-client-archive/',
        strict: true,
    },
});
```

`LocalWebCache` resolves `<path>/<webVersion>.html` and serves it in place of
the live page. With `strict: false` it silently falls back to live if the file
is missing, which hides typos — prefer `strict: true` when you mean to pin.

## Limitation

The archived HTML only references the JS/CSS bundles; it does not contain them.
They are still fetched from `static.whatsapp.net` at runtime. Once WhatsApp
stops serving a build's bundles, that archived version stops working too. This
buys rollback headroom, not permanent reproducibility.
