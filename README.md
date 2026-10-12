# MathOCR Windows Installer

Unofficial PowerShell installer for the Windows GUI from
[Yu-Zhuohang/MathOCR](https://github.com/Yu-Zhuohang/MathOCR).

The upstream project contains an Electron interface backed by the local
`pix2tex` model, but currently does not publish a ready-to-run Windows release.
This repository automates the source installation.

## What the installer does

- Downloads the upstream MathOCR source from GitHub.
- Installs Python 3.11 and Node.js LTS through `winget` when missing.
- Creates an isolated Python virtual environment.
- Installs CPU-only PyTorch and `pix2tex` dependencies.
- Downloads the formula-recognition model.
- Builds the Electron GUI.
- Creates MathOCR shortcuts on the Desktop and in the Start menu.
- Preserves an existing installation as a timestamped backup during upgrades.

The default installation directory is:

```text
%LOCALAPPDATA%\Programs\MathOCR
```

## Requirements

- Windows 10 or Windows 11, 64-bit
- PowerShell 5.1 or newer
- Internet connection during installation
- `winget` if Python 3.11 or Node.js LTS is not already installed
- Approximately 2 GB of available disk space

## Install

### Recommended: download, inspect, then run

Open PowerShell and run:

```powershell
Invoke-WebRequest `
  https://raw.githubusercontent.com/rping0310/MathOCR-Windows-Installer/main/install.ps1 `
  -OutFile install-mathocr.ps1

notepad .\install-mathocr.ps1
powershell -ExecutionPolicy Bypass -File .\install-mathocr.ps1
```

### One-line installation

Only use this after reviewing `install.ps1`:

```powershell
irm https://raw.githubusercontent.com/rping0310/MathOCR-Windows-Installer/main/install.ps1 | iex
```

To use a different installation directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-mathocr.ps1 `
  -InstallPath "D:\Apps\MathOCR"
```

## Basic usage

1. Start **MathOCR** from the Desktop or Start menu.
2. Wait until the bottom-right status reads **Ready**.
3. Press `Ctrl+Shift+Alt+F`.
4. Drag around one typeset formula.
5. Choose **Copy LaTeX** or **Copy MathML**.

For best results, capture only one printed/typeset formula. The underlying
`pix2tex` model is not designed for paragraphs and is unreliable with
handwriting.

## Troubleshooting

If dependency installation fails after Python or Node.js was newly installed,
close PowerShell, open a new PowerShell window, and run the installer again.

If an upgrade fails, the previous installation remains beside the target as a
folder ending in `-backup-YYYYMMDD-HHMMSS`.

## Attribution and licensing

This repository is an independent installer and is not affiliated with the
upstream author.

- MathOCR GUI: Copyright (c) 2026 Yu Zhuohang, MIT License
- pix2tex / LaTeX-OCR: Copyright (c) Lukas Blecher and contributors, MIT License
- Installer scripts in this repository: MIT License

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for links and details.
