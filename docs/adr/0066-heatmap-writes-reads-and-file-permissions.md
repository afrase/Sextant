# 66. Heatmap writes of 100 presses or more, read-back from cached day sums, and owner-only files

Status: accepted, 2026-10-22. Amends ADR 0053.

## Context
The user asked whether the heatmap's files could expose passwords or what people type, and whether JSON was efficient
enough. Looking into it turned up three things.

- **Short writes give away a password.** ADR 0053 keeps hourly counts, with no key order and no characters. But every
  minute's write adds what was counted that minute, so a write can be tiny. Secure input hides browser and system password
  fields, but not, for example, `sudo` in a terminal without Secure Keyboard Entry. Say you type a password there and
  nothing else that minute, or that hour. That write adds just the password's keys, in some order, and anyone who reads
  the files twice, a minute apart, can tell them from the rest. For a short password that narrows the search a lot.
- **Windows reread everything after each write.** A window showing the Heatmap reads the range's stored hours again
  every time a write lands, which is once a minute while the user types. With a year of counts kept, that is about
  365 files and 9.6 MB of JSON. It took 0.63 s per reread in a release build, nearly all of it decoding; adding the
  hours up took 20 ms. It runs off the main actor, but it holds up the recorder's queue, and every open window repeats it.
- **The files used the default permissions.** Files were 0644 and folders 0755. `~/Library` is already 0700, so other
  users can't get to them today. Owner-only permissions are defense in depth.

SQLite was considered and turned down. Each day file is about 26 KB at most, the files are written whole and atomically
already, and the cost was decoding the same files over and over, not the format. SQLite would need a new package or
hand-written bindings (ADR 0018), plus schema migrations. It would also make encryption harder, if we ever want it,
since that would mean SQLCipher. With JSON, CryptoKit could seal each file. And today you can open a file and see
exactly what is stored.

## Decision
- **Writes of at least 100 presses** (`HeatmapRecorder.defaultMinimumWrite`). At each flush, a layout's unwritten
  hours are taken oldest first. An hour with fewer than 100 presses is carried into the next one, and the merged counts
  are filed under the later hour. Whatever is still short of 100 at the end waits in memory, under its last hour. So
  every hour a write adds to gets at least 100 presses, and a password typed outside secure input always lands among at
  least 100 presses. Layer moves don't count toward the 100; they travel with the presses. Counts held back still show
  in windows and in today's total. They are lost if Sextant quits first, which is at most 99 presses. When counts are
  carried, up to 99 presses can end up in a later hour than the one they were typed in, perhaps on the next day, so
  today's total and the 24-hour range can include a few from yesterday. The heatmap is about positions, so that doesn't
  matter. A flush that carries counts without writing them bumps `changes`, so windows pick up hours that now fall in
  their range. Tests pass `minimumWrite: 0` to write each press at once.
- **The store returns sums.** The `HeatmapStore` port's `hours(of:from:)` becomes `heatmap(of:from:)`, returning the
  range's counts already added up as a `KeyHeatmap`. `HeatmapRecorder.Snapshot` carries that sum instead of the hours.
  No caller ever needed the hours themselves, and a window no longer holds a year of decoded hours (about 40 MB) in
  memory.
- **Each day's sum is cached.** `HeatmapFiles` keeps each day file's counts added up, keyed by path, along with the
  file's modification date and size when it was read. A day wholly inside the range uses its cached sum unless the file
  has changed since. Sextant's own writes, prunes and clears also drop the cached sums they touch. The day the range
  starts in is decoded each time, so that only its hours from the start count. A reread after a write fell from
  0.64 s to 4.4 ms, with a year kept. The first read after launch still decodes every file, once.
- **Owner-only files.** The heatmap folder and each layout's folder are 0700, and each day file is 0600. The folder is
  made the user's alone at launch's prune, or at the first write if there was no folder yet, so a folder an earlier
  Sextant created is fixed too. A day file is set to 0600 right after its atomic write. For that moment it is 0644,
  inside the 0700 folder. A volume that refuses the change is logged, not failed. A write that landed must never report
  failure, or the recorder would retry it and count the hour twice.

## Consequences
- An attacker who can read the user's files sees no write smaller than 100 presses. The data is still not encrypted: a
  process running as the user can still read the hourly counts, by position and layer, as ADR 0053 describes.
- Quitting loses up to 99 counted presses per layout.
- The cache is never evicted. It holds one small sum per day file read, about 365 per layout with a year kept.
- `HeatmapFiles.hours(of:from:)` stays as an internal method, for the contract tests.
