# Contributing

Bug reports, ideas and pull requests are welcome. For anything bigger than a small fix, open an issue first so we can agree on the approach before you write code.

## Setting up

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if Xcode is not your active developer directory
cd Packages/ExhibitCore && swift build && swift test
swiftlint --strict   # from the repo root
```

## Making a pull request

1. Branch from `development`, where work lands before a release. `main` holds what has been released.
2. Keep each pull request to one change, and each commit to one step of it.
3. Run the tests and `swiftlint --strict`. Both must pass.
4. Never weaken `RedactionTests`: output under a blur must not depend on the pixels it hides.

## Contributor terms

Exhibit A is licensed under FSL-1.1-MIT, and some features are or will be sold under a commercial licence. To keep that possible, every contribution comes with these terms. By opening a pull request, you agree that:

1. You wrote the contribution, or otherwise have the right to submit it.
2. You grant Corey Haines a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to use, modify, and distribute your contribution, and to sublicense and relicense it under any terms, including commercial ones.
3. You keep the copyright in your contribution, and you can use it however you like.

If you can't agree to these terms, please open an issue describing the change instead.
