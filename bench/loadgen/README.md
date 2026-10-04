# loadgen

once-campfire-elixir's `bench/loadgen` (MIT, see MIT-LICENSE; upstream commit in UPSTREAM),
the load generator behind the reference README's comparison table, with one change: requests
marked same-origin (`Sec-Fetch-Site: same-origin`) also send `Origin`, as browsers do, because
Soli's forgery protection checks Origin rather than Sec-Fetch-Site.

    CARGO_TARGET_DIR=~/.cache/campfire-loadgen-target cargo build --release
