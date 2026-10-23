# Contributing

Thanks for helping. Bug reports, feature ideas and pull requests are all welcome.

## Before you start

- Open an issue or a discussion for larger changes so we can agree on the approach first.
- Keep changes focused. One feature or fix per pull request.

## Building and testing

```sh
swift build -c release
swift test
```

The app needs macOS 14 or later. Some speech features need macOS 26 and Xcode 26.

## Style

- Swift 5 language mode, four-space indentation, no trailing whitespace.
- Comments explain why, not what. Keep them short and in English.
- Every user-facing string is English.

## Pull requests

Fill in the template. A change to speech tracking should include a sentence on how it was checked, since the unit tests cover the alignment logic but not live speech.

By contributing you agree that your contribution is licensed under GPL-3.0, the same as the project.
