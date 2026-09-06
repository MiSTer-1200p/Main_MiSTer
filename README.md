# MiSTer 1920x1200 Fork

Fork of MiSTer Main binary with 1920x1200 (16:10) framebuffer support.

When rescaling from 4:3 to 16:10, this resolution avoids the need to crop or add borders, resulting in a cleaner image on 16:10 displays.

## What's Changed

- **Framebuffer size**: `FB_SIZE` increased from 1920x1080 to 1920x1200
- **DTB auto-patching**: On first boot, the MiSTer binary automatically patches the kernel DTB to allocate 16 MiB for the framebuffer (up from 8 MiB), then reboots. The original `zImage_dtb` is backed up to `zImage_dtb.orig`.

## Variants

| Branch | Based on | Description |
|---|---|---|
| [master](https://github.com/MiSTer-1200p/Main_MiSTer/tree/master) | [MiSTer-devel](https://github.com/MiSTer-devel/Main_MiSTer) | Official upstream + 1200p |
| [db9](https://github.com/MiSTer-1200p/Main_MiSTer/tree/db9) | [MiSTer-DB9](https://github.com/MiSTer-DB9/Main_MiSTer) | DB9/SNAC8 ENCC support + 1200p |
| [aitorgomez](https://github.com/MiSTer-1200p/Main_MiSTer/tree/aitorgomez) | [spark2k06](https://github.com/spark2k06/Main_MiSTer) | Aitor Gomez firmware + 1200p |
| [full](https://github.com/MiSTer-1200p/Main_MiSTer/tree/full) | MiSTer-DB9 + spark2k06 | Both forks merged + 1200p |

## Installation

Add the following to your `downloader.ini` (or configure via Update All), replacing `<variant>` with `master`, `db9`, `aitorgomez`, or `full`:

```ini
[distribution_mister]
db_url = https://raw.githubusercontent.com/MiSTer-1200p/Main_MiSTer/db/<variant>/db.json.zip
```

For example, for the `full` variant:

```ini
[distribution_mister]
db_url = https://raw.githubusercontent.com/MiSTer-1200p/Main_MiSTer/db/full/db.json.zip
```

This replaces the default MiSTer distribution with the selected variant. All cores and other files remain unchanged from the upstream distribution.

## Building

```bash
docker run --rm -v "$PWD:/build" -w /build theypsilon/gcc-arm:10.2-2020.11 bash -c "make clean && make"
```

The binary will be at `bin/MiSTer`.
