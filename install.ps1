# Magicka Toolkit Lite — установка одной командой.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/Elintirs/game-tools/main/magicka/toolkit/lite/install.ps1')"
#
# Скрипт находит папку Magicka, скачивает чистую сборку тулкита (журнал и мониторинг, без читов) и
# распаковывает её рядом с Magicka.exe. Права администратора нужны, если игра стоит в Program Files.
param([string]$GameDir = "")

$ErrorActionPreference = "Stop"
$zipUrl = "https://raw.githubusercontent.com/Elintirs/magicka-toolkit-lite/main/MagickaToolkit-Lite.zip"
$selfUrl = "https://raw.githubusercontent.com/Elintirs/magicka-toolkit-lite/main/install.ps1"

function Say($text) { Write-Host $text }
function Fail($text) { Write-Host ""; Write-Host $text -ForegroundColor Red; exit 1 }

if (-not $GameDir -and $env:MAGICKA_DIR) { $GameDir = $env:MAGICKA_DIR }

# ---- папка игры ----
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

# ---- игра не должна работать: файлы будут заняты ----
$proc = Get-Process Magicka -ErrorAction SilentlyContinue
if ($proc) { Fail "Magicka запущена. Закрой игру и запусти установку снова." }

$tk = Join-Path $game "MagickaToolkit"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---- скачивание ----
$zip = Join-Path $env:TEMP "MagickaToolkit-Lite.zip"
Say "Скачиваю чистую сборку..."
try {
	Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip
} catch {
	Fail "Не скачалось: $($_.Exception.Message)"
}
if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) { Fail "Архив скачался битым — остановился." }

# ---- распаковка ----
try {
	Expand-Archive -Path $zip -DestinationPath $game -Force
} catch {
	if (-not $admin) {
		Say "Нет прав на запись в папку игры (Program Files). Перезапускаю от имени администратора..."
		$env:MAGICKA_DIR = $game
		Start-Process powershell -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "iex (irm '$selfUrl')")
		exit
	}
	Fail "Не распаковалось: $($_.Exception.Message)"
}
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Say "Установлено: $tk"

# ---- как запускать ----
Say ""
Say "Готово. Дальше — любой из двух способов:"
Say "  1) Запускать игру через  $tk\launch.exe   (он сам поднимает Magicka и подключает тулкит)"
Say "  2) Или в Steam: Magicka → Свойства → Параметры запуска — вставь строку:"
Say "     `"$tk\launch.exe`" %command%"
Say ""
Say "В игре — F2: разделы «Журнал» и «Система». Логи: $tk\logs"
Say "Чистая сборка: без авто-защиты, лечения, техник, песочницы и арены; DLC и робы открыты."
