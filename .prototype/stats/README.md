# SunoPlayer Stats mock-up

Three throwaway variants, all using clearly marked sample data:

- `A`: a compact library snapshot, using data the app already has
- `B`: collection statistics inside Browse, using data the app already has
- `C`: a dedicated listening dashboard, requiring a new local listening-history model

Preview images are available under `previews/`.

Open the prototype:

```sh
open .prototype/stats/index.html
```

Use the bottom arrows or the left and right arrow keys. Each option is directly addressable with `?variant=A`, `?variant=B`, or `?variant=C`.

This branch is for product validation only. No Stats implementation should be promoted directly from this prototype.
