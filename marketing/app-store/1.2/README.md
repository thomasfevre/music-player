# App Store screenshots for SunoPlayer 1.2

The `raw/` directory contains isolated iPhone 17 Pro Max Simulator captures at 1320 × 2868. The `final/` directory contains the composed, upload-ready English screenshots in their intended order.

The device mockup is rendered directly by the generator as a reusable front-facing titanium iPhone. Its screen contour comes from the iPhone 17 Pro Max Simulator alpha mask, so the frame follows Apple's continuous corner geometry instead of a generic rounded rectangle. It does not depend on a Photoshop template or a third-party image asset.

Regenerate the final assets with:

```bash
/Users/toma/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/generate_app_store_screenshots.py
```

The simulator data is synthetic and created only in Debug builds through `UITEST_SEED`. No personal music library data is included.
