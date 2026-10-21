# XHCI.R4D

`XHCI.R4D` is the loadable activation owner for the canonical
kernel-resident R4OS xHCI backend.

## Package

- Version: `0.1.2`
- Image target: `/R4OS/DRIVERS/XHCI.R4D`
- Image scope: `slim`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

The module intentionally contains no second PCI, MMIO, DMA, ring, transfer or
interrupt implementation. DriverApi v21 binds its R4D owner identity to the
kernel backend family. Every matching PCI function has an independent resident
controller instance, IRQ/worker, DMA storage and device generations. Family
unload succeeds only after each instance has acknowledged its own resource
cleanup; an uncertain instance retains its resources. PCI diagnosis identifies
the exact registered function. This activation artifact and USB-v2 ABI remain
unchanged by the multi-controller and wait/HID/DMA changes.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.
