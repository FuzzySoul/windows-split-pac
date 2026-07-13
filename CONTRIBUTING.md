# Contributing

Thanks for improving Windows Split PAC. This repository is a Windows-first desktop tool; please keep user proxy addresses, PAC files, and local logs out of commits and issues.

## Local setup

1. Install Python 3 and Rust stable.
2. Run `python -m pip install -r requirements.txt`.
3. Run `cargo run --release --manifest-path rust-gui/Cargo.toml`.

The GUI can change the current user's Windows proxy settings. Use `scripts/Test-Package.ps1` for isolated PAC validation; it creates a temporary PAC server and does not modify Windows proxy settings.

## Before opening a pull request

```powershell
.\scripts\Test-Package.ps1
cargo fmt --manifest-path rust-gui\Cargo.toml -- --check
cargo clippy --manifest-path rust-gui\Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust-gui\Cargo.toml --all-targets
```

Explain the user-visible behavior, rollback behavior, and test evidence in the pull request. Changes that touch proxy settings must preserve an explicit recovery path.
