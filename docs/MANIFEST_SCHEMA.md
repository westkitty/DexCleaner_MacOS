# Cleanup Manifest Contract

`CleanupManifest.json` is a cleanup-authority document, not a suggestion catalog.

## Top-level fields

- `version`: non-empty policy version
- `name`: non-empty manifest name
- `policy`: non-empty authority statement
- `safeExactTargets`: exact cleanup-authority entries
- `forbiddenFragments`: path fragments that block cleanup

## Entry requirements

Every entry must have:

- unique non-empty `id`
- normalized home-relative `relativePath`
- non-empty `displayName`
- non-empty `group`
- valid category
- `risk` equal to `Safe`
- non-empty explanation
- non-empty recovery note
- `defaultSelected` equal to `false`

## Invalid conditions

The manifest fails closed when any entry:

- duplicates an ID
- duplicates a path
- overlaps another target as ancestor or descendant
- uses an absolute path
- contains parent traversal, dot segments, repeated separators, or other non-canonical aliases
- names a broad root
- uses a non-safe risk
- begins selected
- conflicts with a forbidden fragment
- contains whitespace-padded IDs, metadata, or fragments
- lacks descriptive metadata

A failed manifest yields zero cleanable targets.

## Audit findings

Caution, protected, cloud, large-file, storage-map, and Git findings do not belong in the cleanup-authority manifest. They are generated as audit-only records by the scanner.
