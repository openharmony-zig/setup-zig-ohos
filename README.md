# setup-zig-ohos

This is a simple Github Action to download and setup zig-lang which patched for OpenHarmony. It can help us to use zig in Github Action.

## Example

```yml
name: Main

on: push

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Zig OpenHarmony SDK
        uses: openharmony-zig/setup-zig-ohos@v0.1
```

## Options

### inputs

| Name  | Type    | Default                  | Description                                                                                    |
| ----- | ------- | ------------------------ | ---------------------------------------------------------------------------------------------- |
| tag   | String  | 0.16.0-dev.312+164c598cd | zig version which will download from [zig-patch](https://github.com/openharmony-zig/zig-patch) |
| cache | Boolean | true                     | Uses the GitHub actions cache to cache the SDK when enabled.                                   |

## Support Platforms

- [x] aarch64 mac
- [x] x86_64 window
- [x] x86_64 linux for musl
- [x] x86_64 linux for gnu

## License

[MIT](./LICENSE)
