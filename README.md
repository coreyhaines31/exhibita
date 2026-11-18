# Exhibit A

A Mac menu bar screenshot tool: mark up with single keys, a spoken sentence, or one CLI command from an agent. Free, source available, and everything runs on your Mac.

**Status:** the `exhibit` CLI works on image files today (`docs/cli.md`). The menu bar app is being built; the plan is `docs/product/spec.md`.

```sh
exhibit blur shot.png --kind email --kind key
exhibit arrow shot.png --to "Pricing" --label "Click here"
exhibit say shot.png "blur the emails and circle pricing"
```

## Building

```sh
cd Packages/ExhibitCore && swift build -c release   # .build/release/exhibit
```

## License

[FSL-1.1-MIT](LICENSE) © Corey Haines. Free to use and modify, including at work. You can't resell it or build a competing product from it. Each release becomes MIT two years after it ships. Paid cloud and Teams code will live in `ee/` under its own [commercial licence](ee/LICENSE). See also [TRADEMARK.md](TRADEMARK.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
