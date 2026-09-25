# Required CI and checked cask updates

Every pull request and default-branch push runs `ci`. The required `ci / required`
aggregate depends on the complete native cask and shell validation workflow;
missing, failed, skipped or cancelled lanes cannot pass. Review all jobs and exact
head/base, author/DCO and relevant artifacts before merging. Shared actions,
workflows and presets use immutable `v4.0.0` references. Renovate is the sole
dependency merger: the shared `automerge.json` preset arms GitHub auto-merge with
rebase merges, and GitHub merges only once every required CI and policy check
passes on the current head. Shared Renovate policy updates remain manual;
release-age rules, holds and repository-specific updater ownership still apply.
The legacy Actions merger and its comment commands are retired.

The separate PR policy workflow verifies Conventional Commit titles, genuine
matching author sign-offs, Renovate provenance, holds, outstanding review requests
and unresolved changes requests. After a pass, it re-runs the other event's older
failed verdict for the same head, which needs `actions: write`. Require its actual
emitted policy context alongside all existing application/content checks, pinned
to GitHub Actions, with strict up-to-date branch protection. Preserve stronger review requirements. Explicit CI
dispatches do not substitute for a missing metadata policy result. Review exact
head/base, full diffs and all required results before a bootstrap merge, then
verify resulting default-branch CI. Repository-specific updater ownership and
manual publication or delivery controls remain unchanged.

The existing `brew readall --no-simulate`, `brew style` and `brew audit --cask`
checks run against the exact PR checkout on macOS 26 ARM64. The Linux lane runs
Bash syntax, ShellCheck and five Python fixtures exercising the real rewrite and
discovery scripts: Ruby-valid updates, unsafe version/hash rejection, missing
rewrite anchors, and one-to-one cask/pipeline discovery. Run
`bash .github/scripts/check.sh` locally with Python, Ruby, jq and ShellCheck.
CI rejects tracked-file changes. Native Homebrew validation remains required;
Linux syntax/fixture checks are not a substitute for the macOS result.

The existing sequential updater still resolves/downloads/hashes upstream assets,
publishes rolling releases and optionally reports VirusTotal results. It now
proposes only the generated cask on `fix/update-cask-<token>`; nothing is
dispatched. `CASK_PUBLISHER_TOKEN` is a dedicated fine-grained token restricted to
`edbfi/homebrew-taps`, with Contents and Pull requests read/write and Metadata
read. Only the final create-pull-request step receives it, so branch publication
triggers normal PR CI without the recurring GITHUB_TOKEN approval gate. The
reusable publisher requires this secret and has no fallback. The repository token
continues to handle reads and release publication. Both publisher jobs are
restricted to the trusted default branch; PR execution never receives the
publishing credential. The scheduled updater and keepalive run only on the
configured default branch. The dedicated edbfi WORKFLOW_KEEPALIVE_TOKEN-backed
keepalive and optional VirusTotal configuration are preserved. Cask versions,
checksums, resolver rules, existing release assets and vendored keepalive source
are preserved. The updater checks out its exact triggering revision and requires
the newest main CI run for that SHA to have completed successfully, whether
triggered by a push or an explicit dispatch.

Renovate's Homebrew manager is disabled because the cask updater owns verified re-hosted
versions/checksums. The macOS CI does not launch applications; the updater now inspects bundle identity
and architectures before publication. VirusTotal remains optional. Published assets are preserved while cask PRs await manual review. The Linux integration adds reusable formulae.yml to the same required gate. It
builds all four source formulae on native Ubuntu ARM64 and x86_64, runs linkage,
strict audits and X11/Wayland GUI checks, then locally reinstalls the three eligible
bottles and repeats checks. Fred TV stays source-installed. Complete combined
bottle/source artifacts are verified in a read-only aggregation job. Neither
Linux source resolution nor release publication runs automatically; recipe updates
require a reviewed PR. Existing keepalive credentials remain unchanged.
