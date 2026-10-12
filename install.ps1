[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "Programs\MathOCR")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$UpstreamRepository = "https://github.com/Yu-Zhuohang/MathOCR"
$SourceArchive = "$UpstreamRepository/archive/refs/heads/main.zip"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Install-WithWinget {
    param(
        [string]$Id,
        [string]$DisplayName
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "$DisplayName is required, but winget is unavailable. Install App Installer from Microsoft Store, then run this script again."
    }

    Write-Step "Installing $DisplayName"
    & $winget.Source install --id $Id --exact --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install $DisplayName (exit code $LASTEXITCODE)."
    }
    Refresh-Path
}

function Find-Python311 {
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source -3.11 -c "import sys; assert sys.version_info[:2] == (3, 11)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            return @{ Command = $py.Source; Prefix = @("-3.11") }
        }
    }

    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python) {
        & $python.Source -c "import sys; assert sys.version_info[:2] == (3, 11)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            return @{ Command = $python.Source; Prefix = @() }
        }
    }
    return $null
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

Write-Host "MathOCR Windows Installer" -ForegroundColor Green
Write-Host "Upstream: $UpstreamRepository"
Write-Host "Install location: $InstallPath"

$pythonInfo = Find-Python311
if (-not $pythonInfo) {
    Install-WithWinget -Id "Python.Python.3.11" -DisplayName "Python 3.11"
    $pythonInfo = Find-Python311
    if (-not $pythonInfo) {
        throw "Python 3.11 was installed but could not be found. Open a new PowerShell window and run the installer again."
    }
}

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or
    -not (Get-Command npm.cmd -ErrorAction SilentlyContinue) -or
    -not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) {
    Install-WithWinget -Id "OpenJS.NodeJS.LTS" -DisplayName "Node.js LTS"
}

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npm -or -not $npx) {
    throw "Node.js was installed but npm/npx could not be found. Open a new PowerShell window and run the installer again."
}

$installParent = Split-Path -Parent $InstallPath
New-Item -ItemType Directory -Path $installParent -Force | Out-Null
$workRoot = Join-Path $installParent (".MathOCR-install-" + [Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $workRoot "MathOCR.zip"
$backupPath = $null

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    Write-Step "Downloading MathOCR source"
    Invoke-WebRequest -Uri $SourceArchive -OutFile $archivePath -UseBasicParsing
    Expand-Archive -LiteralPath $archivePath -DestinationPath $workRoot -Force
    $sourceDir = Get-ChildItem -LiteralPath $workRoot -Directory |
        Where-Object { $_.Name -like "MathOCR-*" } |
        Select-Object -First 1
    if (-not $sourceDir) {
        throw "The downloaded MathOCR archive did not contain the expected source folder."
    }

    Write-Step "Creating isolated Python environment"
    $venvArgs = @($pythonInfo.Prefix) + @("-m", "venv", (Join-Path $sourceDir.FullName ".venv"))
    Invoke-External -FilePath $pythonInfo.Command -Arguments $venvArgs
    $venvPython = Join-Path $sourceDir.FullName ".venv\Scripts\python.exe"

    Write-Step "Installing the CPU-only OCR engine"
    Invoke-External -FilePath $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip")
    Invoke-External -FilePath $venvPython -Arguments @(
        "-m", "pip", "install", "torch", "torchvision",
        "--index-url", "https://download.pytorch.org/whl/cpu"
    )
    Invoke-External -FilePath $venvPython -Arguments @(
        "-m", "pip", "install", "-r", (Join-Path $sourceDir.FullName "engine\requirements.txt")
    )

    Write-Step "Downloading the pix2tex model"
    $env:NO_ALBUMENTATIONS_UPDATE = "1"
    Invoke-External -FilePath $venvPython -Arguments @(
        "-c", "from pix2tex.cli import LatexOCR; LatexOCR(); print('pix2tex model ready')"
    )

    Write-Step "Preparing the MathOCR desktop interface"
    $sidecarPath = Join-Path $sourceDir.FullName "electron\sidecar.ts"
    $sidecar = Get-Content -LiteralPath $sidecarPath -Raw
    $needle = '  private findPython(): string {'
    if (-not $sidecar.Contains($needle)) {
        throw "The upstream sidecar layout changed; refusing to apply an unsafe patch."
    }
    $replacement = @'
  private findPython(): string {
    // Prefer the isolated environment created by MathOCR-Windows-Installer.
    const bundledVenvPython = process.platform === "win32"
      ? path.resolve(__dirname, "..", "..", ".venv", "Scripts", "python.exe")
      : path.resolve(__dirname, "..", "..", ".venv", "bin", "python");
    try {
      if (require("fs").existsSync(bundledVenvPython)) return bundledVenvPython;
    } catch {}

'@
    $sidecar = $sidecar.Replace($needle, $replacement)
    Set-Content -LiteralPath $sidecarPath -Value $sidecar -Encoding UTF8

    Push-Location $sourceDir.FullName
    try {
        Invoke-External -FilePath $npm.Source -Arguments @("install", "--no-audit", "--no-fund")
        Invoke-External -FilePath $npx.Source -Arguments @("tsc", "-p", "tsconfig.json")
        Invoke-External -FilePath $npx.Source -Arguments @("tsc", "-p", "tsconfig.electron.json")
        Copy-Item "src\index.html" "dist\renderer\index.html" -Force
        Copy-Item "src\style.css" "dist\renderer\style.css" -Force
        Copy-Item "electron\overlay.html" "dist\electron\overlay.html" -Force
    }
    finally {
        Pop-Location
    }

    Write-Step "Installing MathOCR"
    if (Test-Path -LiteralPath $InstallPath) {
        $backupPath = "$InstallPath-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item -LiteralPath $InstallPath -Destination $backupPath
        Write-Host "Previous installation preserved at: $backupPath" -ForegroundColor Yellow
    }
    Move-Item -LiteralPath $sourceDir.FullName -Destination $InstallPath

    $electronExe = Join-Path $InstallPath "node_modules\electron\dist\electron.exe"
    if (-not (Test-Path -LiteralPath $electronExe)) {
        throw "Electron executable is missing after installation."
    }

    Write-Step "Creating shortcuts"
    $shell = New-Object -ComObject WScript.Shell
    $shortcutLocations = @(
        (Join-Path ([Environment]::GetFolderPath("Desktop")) "MathOCR.lnk"),
        (Join-Path ([Environment]::GetFolderPath("Programs")) "MathOCR.lnk")
    )
    foreach ($shortcutPath in $shortcutLocations) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $electronExe
        $shortcut.Arguments = '"' + $InstallPath + '"'
        $shortcut.WorkingDirectory = $InstallPath
        $shortcut.IconLocation = "$electronExe,0"
        $shortcut.Description = "MathOCR - screenshot formulas to LaTeX and MathML"
        $shortcut.Save()
    }

    Write-Host "`nMathOCR installation completed." -ForegroundColor Green
    Write-Host "Launch it from the MathOCR desktop or Start menu shortcut."
    Write-Host "Screenshot shortcut: Ctrl+Shift+Alt+F"
    Write-Host "Note: pix2tex works best with typeset single formulas; handwriting and prose are not reliable."
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
