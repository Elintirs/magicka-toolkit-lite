# Magicka Toolkit Lite + Community Patch — установка и обновление одной командой.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/Elintirs/magicka-toolkit-lite/main/install.ps1')"
#
# Что делает:
#   1) находит папку Magicka (реестр Steam + libraryfolders.vdf, иначе спросит);
#   2) ставит Community Patch 0.0.60 из его официального релиза на GitHub (Magicka.exe, PolygonHead.dll,
#      Magicka.GcDiagnostics.dll + gc-diagnostics + patch-settings.ini без телеметрии и автообновления);
#      оригинальные файлы один раз сохраняются в MagickaToolkit\backup;
#   3) ставит чистую сборку тулкита (журнал и мониторинг, без читов) в MagickaToolkit.
# Скрипт можно запускать повторно — это и есть обновление.
param([string]$GameDir = "", [switch]$NoPatch, [switch]$NoToolkit)

$ErrorActionPreference = "Stop"
$patchUrl = "https://github.com/Alexander-Aue-Johr/magicka-patch/releases/download/0.0.60/magicka-community-patch-0.0.60-files-only.zip"
$zipUrl = "https://raw.githubusercontent.com/Elintirs/magicka-toolkit-lite/main/MagickaToolkit-Lite.zip"
$selfUrl = "https://raw.githubusercontent.com/Elintirs/magicka-toolkit-lite/main/install.ps1"

function Say($text) { Write-Host $text }
function Fail($text) { Write-Host ""; Write-Host $text -ForegroundColor Red; exit 1 }

if (-not $GameDir -and $env:MAGICKA_DIR) { $GameDir = $env:MAGICKA_DIR }

function Find-Game {
	if ($GameDir -and (Test-Path (Join-Path $GameDir "Magicka.exe"))) { return $GameDir }
	$libs = @()
	$steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
	if (-not $steam) { $steam = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath }
	if ($steam) {
		$libs += $steam
		$vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
		if (Test-Path $vdf) {
			foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value.Replace("\\", "\") }
		}
	}
	$libs += @("C:\Program Files (x86)\Steam", "C:\Program Files\Steam", "D:\Steam", "D:\SteamLibrary", "E:\SteamLibrary", "F:\SteamLibrary")
	foreach ($l in $libs) {
		$g = Join-Path $l "steamapps\common\Magicka"
		if (Test-Path (Join-Path $g "Magicka.exe")) { return $g }
	}
	return $null
}

$game = Find-Game
if (-not $game) {
	Say "Не нашёл Magicka автоматически."
	$game = Read-Host "Впиши папку игры (где лежит Magicka.exe)"
}
if (-not (Test-Path (Join-Path $game "Magicka.exe"))) { Fail "В папке $game нет Magicka.exe — остановился." }
$game = (Resolve-Path $game).Path
Say "Игра: $game"

$proc = Get-Process Magicka -ErrorAction SilentlyContinue
if ($proc) { Fail "Magicka запущена. Закрой игру и запусти снова." }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$tk = Join-Path $game "MagickaToolkit"
$tmp = Join-Path $env:TEMP ("magicka-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Download($url, $file) {
	try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file -TimeoutSec 300 }
	catch { Fail "Не скачалось: $url`n$($_.Exception.Message)" }
	if (-not (Test-Path $file) -or (Get-Item $file).Length -lt 10000) { Fail "Файл скачался битым: $url" }
}

function Set-Laa([string]$path) {
	$bytes = [System.IO.File]::ReadAllBytes($path)
	$pe = [BitConverter]::ToInt32($bytes, 0x3C)
	if ($pe -le 0 -or $pe -ge $bytes.Length - 64) { return $false }
	$ch = [BitConverter]::ToUInt16($bytes, $pe + 22)
	if (($ch -band 0x20) -ne 0) { return $false }
	$new = $ch -bor 0x20
	$bytes[$pe + 22] = [byte]($new -band 0xFF)
	$bytes[$pe + 23] = [byte](($new -shr 8) -band 0xFF)
	[System.IO.File]::WriteAllBytes($path, $bytes)
	return $true
}

# ---- Community Patch 0.0.60 ----
if (-not $NoPatch) {
	Say ""
	Say "Community Patch 0.0.60 (официальный релиз с GitHub)..."
	$patchZip = Join-Path $tmp "patch.zip"
	Download $patchUrl $patchZip
	$patchDir = Join-Path $tmp "patch"
	Expand-Archive -Path $patchZip -DestinationPath $patchDir -Force
	if (-not (Test-Path (Join-Path $patchDir "Magicka.exe"))) { Fail "В архиве патча нет Magicka.exe — остановился." }

	$backup = Join-Path $tk "backup"
	New-Item -ItemType Directory -Force -Path $backup | Out-Null
	foreach ($f in @("Magicka.exe", "PolygonHead.dll")) {
		$orig = Join-Path $game $f
		$keep = Join-Path $backup $f
		if ((Test-Path $orig) -and -not (Test-Path $keep)) {
			Copy-Item $orig $keep -Force
			Say "  оригинал сохранён: MagickaToolkit\backup\$f"
		}
	}
	foreach ($f in @("Magicka.exe", "PolygonHead.dll", "Magicka.GcDiagnostics.dll")) {
		Copy-Item (Join-Path $patchDir $f) (Join-Path $game $f) -Force
		Say "  $f"
	}
	$gcSrc = Join-Path $patchDir "gc-diagnostics"
	if (Test-Path $gcSrc) {
		$gcDst = Join-Path $game "CommunityPatch\GcDiagnostics"
		New-Item -ItemType Directory -Force -Path $gcDst | Out-Null
		Copy-Item (Join-Path $gcSrc "*") $gcDst -Force
		Say "  CommunityPatch\GcDiagnostics"
	}
	# телеметрия и автообновление выключены: версия остаётся 0.0.60, как у второго игрока
	$iniSrc = Join-Path $patchDir "patch-settings.ini"
	$cpDir = Join-Path $game "CommunityPatch"
	New-Item -ItemType Directory -Force -Path $cpDir | Out-Null
	if (Test-Path $iniSrc) {
		$ini = Get-Content $iniSrc -Raw -Encoding UTF8
		foreach ($k in @("usage_sharing", "crash_reports", "check_for_updates", "auto_update")) { $ini = $ini.Replace("$k=true", "$k=false") }
		Set-Content -Path (Join-Path $cpDir "patch-settings.ini") -Value $ini -Encoding UTF8
		Say "  CommunityPatch\patch-settings.ini (телеметрия и обновления выключены)"
	}
	if (Set-Laa (Join-Path $game "Magicka.exe")) { Say "  Magicka.exe: Large Address Aware (4 ГБ)" }
}

# ---- Magicka Toolkit Lite ----
if (-not $NoToolkit) {
	Say ""
	Say "Magicka Toolkit Lite (журнал и мониторинг, без читов)..."
	$zip = Join-Path $tmp "toolkit.zip"
	Download $zipUrl $zip
	try {
		Expand-Archive -Path $zip -DestinationPath $game -Force
	} catch {
		if (-not $admin) {
			Say "Нет прав на запись в папку игры (Program Files). Перезапускаю от имени администратора..."
			$env:MAGICKA_DIR = $game
			Start-Process powershell -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "iex (irm '$selfUrl')")
			exit
		}
		throw
	}
	Say "  $tk"
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Say ""
Say "Готово. Дальше — любой из двух способов:"
Say "  1) Запускать игру через  $tk\launch.exe   (он сам поднимает Magicka и подключает тулкит)"
Say "  2) Или в Steam: Magicka → Свойства → Параметры запуска — вставь строку:"
Say "     `"$tk\launch.exe`" %command%"
Say ""
Say "В игре — F2: разделы «Журнал» и «Система». Логи: $tk\logs"
Say "Не запускай в Steam «Проверить целостность файлов» — она вернёт старый Magicka.exe и снесёт патч."
Say "Повторный запуск этой команды = обновление."
