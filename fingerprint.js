'use strict';

// Comparing two archived pages byte-for-byte does not work. WhatsApp stamps
// every response with a CSP nonce, a request id (brsid), a ServerNonce, a React
// mount id and a request timestamp, plus data-content-len fields that shift as a
// consequence. Two fetches of the *same* version differ by ~28 bytes across ~60
// lines. Normalising all of that away is a losing game: a token type we do not
// know about yet would silently make every run look like a change.
//
// Instead we fingerprint only what is stable and meaningful. The bundle URLs
// under static.whatsapp.net/rsrc.php are content-addressed, so they change
// exactly when the shipped code changes — verified identical across independent
// fetches of one version, which is the property byte comparison lacks.

const BUNDLE_RE = /https:\/\/static\.whatsapp\.net\/rsrc\.php\/[A-Za-z0-9_/.-]+/g;
const BTMANIFEST_RE = /data-btmanifest="([^"]*)"/;
const BOOTLOADER_RE = /data-bootloader-hash="([^"]*)"/g;

const uniqSorted = (values) => [...new Set(values)].sort();

const fingerprint = (html) => ({
    build: (html.match(BTMANIFEST_RE) || [])[1] ?? null,
    bundles: uniqSorted(html.match(BUNDLE_RE) || []),
    bootloaders: uniqSorted([...html.matchAll(BOOTLOADER_RE)].map((m) => m[1])),
    bytes: html.length,
});

const jaccard = (a, b) => {
    const A = new Set(a);
    const B = new Set(b);
    if (A.size === 0 && B.size === 0) return 1;
    let intersection = 0;
    for (const value of A) if (B.has(value)) intersection++;
    return intersection / (A.size + B.size - intersection);
};

const compare = (older, newer) => {
    const olderBundles = new Set(older.bundles);
    const newerBundles = new Set(newer.bundles);
    return {
        bundleSimilarity: jaccard(older.bundles, newer.bundles),
        bootloaderSimilarity: jaccard(older.bootloaders, newer.bootloaders),
        added: newer.bundles.filter((b) => !olderBundles.has(b)),
        removed: older.bundles.filter((b) => !newerBundles.has(b)),
        sameBuild: older.build === newer.build,
        byteDelta: newer.bytes - older.bytes,
    };
};

// Rough guidance, not a guarantee. A build that replaced most of its bundles is
// far likelier to have moved the internals whatsapp-web.js reaches into.
const risk = (result) => {
    if (result.sameBuild && result.bundleSimilarity === 1) return 'identical';
    if (result.bundleSimilarity >= 0.8) return 'low';
    if (result.bundleSimilarity >= 0.5) return 'moderate';
    return 'high';
};

// "2.3000.1043972371" — compare component-wise so 1043972371 does not sort
// before 999, which is what a plain string sort would do.
const compareVersions = (a, b) => {
    const pa = a.split('.').map(Number);
    const pb = b.split('.').map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
        if (diff !== 0) return diff;
    }
    return 0;
};

module.exports = { fingerprint, compare, risk, jaccard, compareVersions };
