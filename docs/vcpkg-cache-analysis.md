# Why the full build never uses the vcpkg binary cache

**Run analysed:** `logs_109211390248` — 2026-10-26, `kicad-package.yml` @ `c26cc9f` (master), runner image `windows-2022` `20261022.344.1`
**Jobs:** `create_full_package` (cancelled) / `create_portable_package` (success)
**Verdict:** the cache is being restored, but it delivers **zero** usable packages. Every run rebuilds all 138 vcpkg ports from source, which is 70–78 % of each job's runtime — and is what pushes the full build into GitHub's 6-hour job timeout.

---

## 1. TL;DR

| # | Defect | Evidence | Impact |
|---|--------|----------|--------|
| 1 | Restored cache is never consumed: `Restored 0 package(s)` | full job `09:12:14` , portable `09:16:16` | 100 % of vcpkg deps rebuilt every run |
| 2 | Cache key is unique per run (`github.run_id`) → no exact-key hit is possible, only a `restore-keys` prefix fallback | key `vcpkg-Windows-40296475662`, restored `vcpkg-Windows-39938260572` | you never control *which* generation you get |
| 3 | Both jobs save the **same** key → one save always fails | `15:05:55 Failed to save: Unable to reserve cache ... another job may be creating this cache` | the freshest (5.30 GB) cache is thrown away in ~50 % of runs |
| 4 | Save runs with `if: always()` → cancelled/failed runs publish partial archives | full job saved after being cancelled | partial entries become the newest prefix match → poison the pool |
| 5 | ABI inputs are unpinned (registry at `HEAD`, toolset from the hosted image) | `Fetching registry information from ... (HEAD)` ×2 | even a good entry can stop matching overnight |

**Cost:** ~7 h of duplicated vcpkg compilation per workflow run (4 h 24 m + 2 h 36 m), ~5.7 GB of downloads that are used for nothing, 5.3 GB uploaded, and the full job dying at exactly 6 h 00 m 45 s — the default `timeout-minutes: 360`.

---

## 2. What the logs actually say

### 2.1 The restore "succeeds"

Full job, `create_full_package`:

```
09:02:12  Run actions/cache/restore@v4
            path: C:\Users\runneradmin\AppData\Local\vcpkg\archives
            key:  vcpkg-Windows-40296475662
            restore-keys: vcpkg-Windows-
09:02:13  Cache hit for restore-key: vcpkg-Windows-39938260572
09:02:34  Cache Size: ~2858 MB (2997323811 B)
09:02:46  Cache restored successfully
09:02:47  Cache restored from key: vcpkg-Windows-39938260572
```

So a 2.86 GB archive is downloaded and extracted in ~35 s (13 s download @ ~140 MB/s).

### 2.2 …but vcpkg consumes none of it

```
09:11:26  -- Running vcpkg install
09:11:48  Fetching registry information from https://github.com/microsoft/vcpkg (HEAD)
09:11:53  Fetching registry information from https://gitlab.com/kicad/packaging/kicad-vcpkg-registry.git (HEAD)
09:11:55  Loading dependency information for 113 packages...
09:12:07  Detecting compiler hash for triplet x64-windows...
09:12:14  The following packages will be built and installed:      <-- 138 ports
09:12:14  Restored 0 package(s) from C:\Users\runneradmin\AppData\Local\vcpkg\archives in 1.89 ms.
```

The portable job is identical: `Restored 0 package(s) ... in 1.5 ms`.

Two things follow from these two lines together:

* vcpkg is scanning **the same directory string** the cache step targets, so this is not a "wrong path" mistake in the YAML.
* No step between the restore and the install deletes that directory (`-Config`, `-Init`, `-Env`, `-Vcpkg` only download tools and clone vcpkg; `build.ps1` never touches `%LOCALAPPDATA%\vcpkg`).
* Therefore the archives were **present but unmatched** — the lookup failed on ABI, not on file existence.

### 2.3 The 138 ports are then rebuilt for 4–4.5 hours

```
09:12:14  Installing 1/138 vcpkg-cmake-config ...   (each one uploaded back to the same cache:
13:35:54  Installing 138/138 zstd  ...               "Starting submission ... to 1 binary cache(s)")
```

### 2.4 The save step is structurally broken

Full job:

```
15:02:47  Run actions/cache/save@v4   (if: always(), after job cancellation)
15:05:55  Failed to save: Unable to reserve cache with key vcpkg-Windows-40296475662,
          another job may be creating this cache.
15:05:56  ##[warning]Cache save failed.
```

Portable job (finished first, 12:39):

```
12:41:33  Cache saved with key: vcpkg-Windows-40296475662        (5,295,552,289 B uploaded)
```

Both jobs use `key: vcpkg-${{ runner.os }}-${{ github.run_id }}` — the *same* key inside one run. Whoever finishes first wins; the other one spends ~3 minutes tarring 5 GB and is then rejected.

### 2.5 The restored entry is not even a complete dependency set

| | size |
|---|---|
| Restored entry (`39938260572`) | 2.86 GB |
| Entry produced by this run (`40296475662`) | 5.30 GB |

A complete 138-port archive is ~5.3 GB. The entry that was restored is ~54 % of that, i.e. it was produced either by an interrupted run (`if: always()` saving a half-filled `archives/`), or by a run with a different dependency set. Either way it cannot satisfy the current build — consistent with `Restored 0`.

---

## 3. Root-cause chain

### R1 — The archives never match, because the ABI key includes inputs the pipeline doesn't control (primary)

vcpkg's binary-cache lookup is keyed on a package ABI that is derived from: the port's content hash, the triplet, the resolved features, **and** the detected toolchain/compiler. The log shows all three of the unstable inputs being re-resolved on every single run:

* `Fetching registry information from https://github.com/microsoft/vcpkg (HEAD)` — the builtin registry is resolved at **HEAD**, not at the commit the job just checked out. Note `build.ps1` pins `$vcpkgCommit = c6928dfb...` and runs `git reset --hard` in manifest mode — that pin is *cosmetic*, because the manifest then asks vcpkg to resolve ports from upstream master anyway.
* `Fetching registry information from https://gitlab.com/kicad/packaging/kicad-vcpkg-registry.git (HEAD)` — 113 of the 138 packages come from a second registry that is also floating on HEAD.
* `Detecting compiler hash for triplet x64-windows...` — the toolset comes from the hosted image, which is refreshed roughly weekly (this run: image `20261022.344.1`, MSVC `14.44.35207`). A toolset bump on the image silently invalidates **every** cached binary at once.

Any single one of these moving produces a miss; all of them moving produces exactly what we see: `0 / 138`. That is the difference between "the cache is broken" and "the cache is a lottery".

### R2 — The key policy guarantees you get an arbitrary, stale generation

`key: vcpkg-${{ runner.os }}-${{ github.run_id }}` can never hit exactly, so every restore is served by `restore-keys: vcpkg-Windows-` → "most recently created entry with this prefix". Combined with R1 that means you are downloading several GB of *probabilistically useless* data on every run.

Worse, the arithmetic of GitHub's cache quota makes a warm entry nearly impossible to keep:

* Repo cache limit: **10 GB** total; entries unused for 7 days are evicted.
* Each run writes one **5.3 GB** entry (per-run key, never overwritten).
* ⇒ at most **one** entry survives; each new run's save evicts the previous one, and the LRU/creation ordering decides which of 2.86 GB / 5.30 GB / truncated you get next time.

### R3 — Two jobs, one key: half of all saves are lost work

`create_full_package` and `create_portable_package` run in parallel, need the identical 138 ports, and both write `vcpkg-Windows-<run_id>`. One of them always fails to reserve (proven above). So the run pays **2× 5.3 GB of tar/upload attempts and 2× 4 h of compilation** and keeps one cache.

### R4 — `if: always()` publishes partial caches

A cancelled/failed job still saves whatever is in `archives/` at that moment (the full job here was cancelled at the 6 h mark and still started a save). Those partial entries become the newest prefix match and are then restored by the next run — which is the most plausible origin of the 2.86 GB entry.

### R5 — The full job runs out of time because of R1

```
09:02:02  job start
09:11:26  vcpkg install starts
13:35:54  vcpkg install ends          -> 4 h 23 m 40 s  (78 % of the -Build step)
14:44:06  -Build step ends            -> KiCad compile ~68 min
14:55:14  NSIS packaging starts
15:02:47  ##[error]The operation was canceled.   (6 h 00 m 45 s after start = default 360 min timeout)
15:02:47  cache save still attempted -> fails
```

The job never uploaded an installer. The portable job (2 h 36 m of vcpkg, 3 h 40 m total) survived only because it has less post-processing.

---

## 4. Secondary observations (not the root cause, but worth fixing while we're in there)

1. **"Build vcpkg deps" step does nothing.** `build.ps1 -Vcpkg` skips `vcpkg install` when `vcpkg.manifest_mode` is true (it only clones + bootstraps vcpkg: 27 s / 17 s). The real install happens implicitly inside `-Build` at CMake configure time — which is why the 4 h 24 m is attributed to the `-Build` step and why the step name is misleading when reading timings.
2. **`git reset --hard $vcpkgCommit` is wasted work** in manifest mode (see R1) — it pins the local checkout while the manifest resolves HEAD. Either pin the manifest (commit `builtin-baseline`, or a registry `baseline`) or drop the reset.
3. **No compilation cache for KiCad itself** — 68 min of MSVC compile per job could go through `ccache`/`sccache` (`VCPKG`-independent), which is a separate ~1 h/run saving.
4. **Cache restore happens before `-Init`** — harmless today, but the 35 s restore is repeated in both jobs for a 2.86 GB artifact that is discarded.
5. **Deprecated actions**: `actions/checkout@v3` and Node 20 targets (warning at the end of both jobs).
6. **`find-latest-tag` runs before checkout in both jobs** and pins asset names — fine, but it means the two jobs can in theory disagree if a release lands mid-run.

---

## 5. Proposed fix, in order of value/risk

### Phase 0 — Make the failure visible (30 min, no behaviour change)
Add a diagnostic step right after the restore, before `-Build`:

```yaml
- name: Inspect vcpkg cache
  shell: pwsh
  run: |
    $p = "$env:LOCALAPPDATA\vcpkg\archives"
    if (Test-Path $p) {
      $z = Get-ChildItem $p -Filter *.zip -ErrorAction SilentlyContinue
      "archives: $($z.Count) zips, $([math]::Round(($z | Measure-Object Length -Sum).Sum/1GB,2)) GB"
      $z | Select-Object -First 5 -ExpandProperty Name
    } else { "MISSING: $p" }
```
This single step distinguishes the only two remaining hypotheses (empty/misplaced directory vs ABI mismatch) in one run, and should stay permanently as a health check. If it prints ~140 zips and vcpkg still says `Restored 0`, R1 is confirmed and only Phase 2 can fix it.

### Phase 1 — Cache hygiene (30 min, removes ~50 % of wasted bytes)
* Replace the per-run key with a **stable, rotating key**: `vcpkg-${{ runner.os }}-${{ env.VCPKG_CACHE_EPOCH }}` where `VCPKG_CACHE_EPOCH` is a manually bumped week number (e.g. `2026w43`), plus `restore-keys: vcpkg-${{ runner.os }}-` for cross-epoch fallback. First run of an epoch saves; the rest hit exactly.
* **Save from one job only.** Either `if: github.job == 'create_full_package'`, or (better) move the dependency build into its own `build-vcpkg-deps` job that both package jobs `needs:`.
* Replace `if: always()` with `if: success() && steps.<deps>.outcome == 'success'`, so cancelled runs never publish half an archive.
* Drop `actions/cache/restore` + `save` in favour of a single `actions/cache@v4` in the deps job (it restores and saves atomically and knows not to re-save an unchanged key).

### Phase 2 — Pin the ABI inputs (the actual cure)
* Pin the dependency graph: add `"builtin-baseline"` to the manifest used by the build (or a `baseline` on the `kicad-vcpkg-registry` git registry), so `Fetching ... (HEAD)` becomes `Fetching ... (<sha>)`. This is what makes a cache entry reproducible across days.
* Stop letting the toolset drift silently: record `cl.exe` version + `vcpkg version` into the cache key so a toolset bump *rotates* the key instead of silently missing (`vcpkg-<os>-<epoch>-<msvc>`).
* Then `git reset --hard $vcpkgCommit` becomes meaningful again (or can be removed).

### Phase 3 — Structural (the real win)
* **One dependency build per run.** Introduce `build-vcpkg-deps` → publish the `archives/` dir (or the whole `vcpkg_installed` tree) as an artifact; both packaging jobs restore it. Removes ~2.5–4.5 h of duplicated compilation *even when the GitHub cache misses*.
* **Move the binary cache off GitHub's cache.** `build.ps1` already ships `s5cmd`; a filesystem/S3 binary cache (`VCPKG_BINARY_SOURCES=clear;files,<path>;readwrite` pointed at S3 or an Azure blob) has no 10 GB quota, no 7-day eviction, and can be shared with the Jenkins pipeline. This is the only design that survives R1's churn gracefully, because old ABIs simply accumulate.
* Add `timeout-minutes` explicitly (e.g. 420 on the full job) so a future regression fails loudly instead of being silently cancelled at 360 min.

---

## 6. Expected effect

| Metric | Now | After Phase 0–2 | After Phase 3 |
|---|---|---|---|
| vcpkg deps, full job | 4 h 24 m | ~10 min (restore + verify) | ~10 min, built **once** per run |
| vcpkg deps, portable job | 2 h 36 m | ~10 min | 0 (artifact reuse) |
| Full job wall clock | 6 h 04 m → **timeout** | ~1 h 45 m | ~1 h 45 m |
| Portable job wall clock | 3 h 40 m | ~50 min | ~50 min |
| Cache traffic per run | 5.7 GB down + 5.3 GB up (unusable) | ~2.9 GB down, 1 save/epoch | ~2.9 GB down |
| Installer produced | **no** (cancelled) | yes | yes |

---

## 7. How to verify each fix

1. After Phase 0: the `Inspect vcpkg cache` step must print a non-zero zip count; the vcpkg line must change from `Restored 0 package(s)` to `Restored 138 package(s)`.
2. After Phase 1: a second run within the same epoch must log `Cache restored from key: vcpkg-Windows-<epoch>` (an *exact* key hit, no `restore-key` fallback) and no `Failed to save`.
3. After Phase 2: two runs a week apart must both report `Restored 138 package(s)` — that is the ABI-drift regression test.
4. Watch for `Starting submission of ... to 1 binary cache(s)` disappearing in steady state: when the cache is warm, vcpkg has nothing to submit.

## Appendix — raw evidence

```
# full job, cache restore
09:02:12.990  path: C:\Users\runneradmin\AppData\Local\vcpkg\archives
09:02:12.990  key: vcpkg-Windows-40296475662
09:02:13.446  Cache hit for restore-key: vcpkg-Windows-39938260572
09:02:34.016  Cache Size: ~2858 MB (2997323811 B)
09:02:46.992  Cache restored successfully

# full job, vcpkg
09:11:48.494  Fetching registry information from https://github.com/microsoft/vcpkg (HEAD)
09:11:53.329  Fetching registry information from https://gitlab.com/kicad/packaging/kicad-vcpkg-registry.git (HEAD)
09:12:14.571  Compiler found: .../MSVC/14.44.35207/bin/Hostx64/x64/cl.exe
09:12:14.706  The following packages will be built and installed:
09:12:14.723  Restored 0 package(s) from C:\Users\runneradmin\AppData\Local\vcpkg\archives in 1.89 ms.

# portable job, same story
09:02:11.473  Cache hit for restore-key: vcpkg-Windows-39938260572
09:02:44.682  Cache restored successfully
09:16:16.866  Restored 0 package(s) from C:\Users\runneradmin\AppData\Local\vcpkg\archives in 1.5 ms.
12:41:33.734  Cache saved with key: vcpkg-Windows-40296475662   (5,295,552,289 B)

# full job, save + cancellation
15:02:47.138  Aborting on Ctrl+C... / ##[error]The operation was canceled.
15:05:55.971  Failed to save: Unable to reserve cache with key vcpkg-Windows-40296475662
```
