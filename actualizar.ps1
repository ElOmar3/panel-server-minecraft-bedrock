# =============================================================
#  actualizar.ps1 - Verificacion y descarga de actualizaciones
#  Minecraft Bedrock Dedicated Server
# =============================================================

param(
    [switch]$Forzar   # Usa -Forzar para actualizar aunque la version sea igual
)

$ServerDir = $PSScriptRoot
$RespDir = Join-Path $ServerDir "resp"
$VersionFile = Join-Path $ServerDir "version_actual.txt"

# --- Leer version actual ---
function Get-VersionActual {
    if (Test-Path $VersionFile) {
        return (Get-Content $VersionFile -Raw).Trim()
    }
    # Intentar leer desde el nombre del exe
    $exe = Join-Path $ServerDir "bedrock_server.exe"
    if (Test-Path $exe) {
        $ver = (Get-Item $exe).VersionInfo.ProductVersion
        if ($ver) { return $ver }
    }
    return "0.0.0.0"
}

# --- Verificar si una URL de ZIP existe en el CDN de Minecraft ---
function Test-BedrockUrl {
    param([string]$Version)
    $url = "https://www.minecraft.net/bedrockdedicatedserver/bin-win/bedrock-server-$Version.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = "HEAD"
        $req.Timeout = 8000
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0 Safari/537.36"
        $req.Referer = "https://www.minecraft.net/es-mx/download/server/bedrock"
        $req.Headers.Add("Accept-Language", "es-MX,es;q=0.9")
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        return @{ Ok = ($code -ge 200 -and $code -lt 400); Url = $url; Version = $Version }
    }
    catch [System.Net.WebException] {
        $code = [int]$_.Exception.Response.StatusCode
        return @{ Ok = $false; Url = $url; Version = $Version }
    }
    catch {
        return @{ Ok = $false; Url = $url; Version = $Version }
    }
}


# --- Obtener URL y version mas reciente (probando versiones en el CDN) ---
function Get-UltimaVersion {
    param([string]$VersionActual)

    # Parsear version actual
    $parts = $VersionActual -split '\.'
    while ($parts.Count -lt 4) { $parts += '0' }
    $v1 = [int]$parts[0]; $v2 = [int]$parts[1]; $v3 = [int]$parts[2]; $v4 = [int]$parts[3]

    # Minecraft Bedrock numera versiones por anio: 2026=1.26.x, 2027=1.27.x
    # Calculamos el rango de minor segun el anio actual y el siguiente
    $anioActual = (Get-Date).Year
    $minorAnio = $anioActual - 2000         # 2026 -> 26
    $minorSig = $minorAnio + 1             # -> 27 (por si cambio de anio)
    $maxMinor = [Math]::Max($v2 + 6, $minorSig)

    Write-Host "  Sondeando versiones en el CDN de Minecraft ($anioActual)..." -ForegroundColor DarkGray
    Write-Host "  Rango: v$v1.$v2.$v3.$v4 hasta v$v1.$maxMinor.x.x" -ForegroundColor DarkGray

    $candidatos = [System.Collections.Generic.List[string]]::new()

    # 1) Incrementos de patch (digito 4): los mas frecuentes  -> +1 a +20
    for ($d4 = $v4 + 1; $d4 -le $v4 + 20; $d4++) { $candidatos.Add("$v1.$v2.$v3.$d4") }

    # 2) Incrementos de sub-minor (digito 3) dentro del mismo anio -> hasta +10
    for ($d3 = $v3 + 1; $d3 -le $v3 + 10; $d3++) { $candidatos.Add("$v1.$v2.$d3.0") }

    # 3) Saltos de anio (digito 2): cubre hasta el siguiente anio del sistema
    for ($d2 = $v2 + 1; $d2 -le $maxMinor; $d2++) { $candidatos.Add("$v1.$d2.0.0") }

    $encontrada = $null
    foreach ($ver in $candidatos) {
        Write-Host "    Probando v$ver..." -ForegroundColor DarkGray -NoNewline
        $res = Test-BedrockUrl -Version $ver
        if ($res.Ok) {
            Write-Host " [EXISTE]" -ForegroundColor Green
            $encontrada = $res
            # Seguir probando digito 4 para encontrar la MAS reciente dentro de esa rama
            if ($ver -match "^(\d+\.\d+\.\d+)\.(\d+)$") {
                $base = $Matches[1]; $d = [int]$Matches[2]
                for ($next = $d + 1; $next -le $d + 15; $next++) {
                    $verNext = "$base.$next"
                    Write-Host "    Probando v$verNext..." -ForegroundColor DarkGray -NoNewline
                    $r2 = Test-BedrockUrl -Version $verNext
                    if ($r2.Ok) { Write-Host " [EXISTE]" -ForegroundColor Green; $encontrada = $r2 }
                    else { Write-Host " no existe" -ForegroundColor DarkGray; break }
                }
            }
            break
        }
        else { Write-Host " no existe" -ForegroundColor DarkGray }
    }

    if ($encontrada) {
        return @{ Url = $encontrada.Url; Version = $encontrada.Version }
    }

    # Si no encontro version nueva: verificar si la actual aun existe (primera vez / archivo corrupto)
    Write-Host "  No se encontro version mas reciente. Verificando version actual..." -ForegroundColor DarkGray
    $resActual = Test-BedrockUrl -Version $VersionActual
    if ($resActual.Ok) {
        Write-Host "  Version actual confirmada en CDN: v$VersionActual" -ForegroundColor DarkGray
        return @{ Url = $resActual.Url; Version = $VersionActual }
    }

    # Ultimo recurso: entrada manual
    Write-Host ""
    Write-Host "  [!] No se pudo verificar la version automaticamente." -ForegroundColor Yellow
    Write-Host "      Ve a: https://www.minecraft.net/es-es/download/server/bedrock" -ForegroundColor Cyan
    Write-Host "      Clic derecho en 'Descargar' (Windows) -> Copiar enlace y pegalo aqui." -ForegroundColor Cyan
    Write-Host "      (Enter para omitir)" -ForegroundColor DarkGray
    $urlManual = Read-Host "  URL del ZIP"
    if (-not $urlManual) { return $null }
    $verMatch = [regex]::Match($urlManual, '(\d+\.\d+\.\d+\.\d+)')
    $verManual = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { "desconocida" }
    return @{ Url = $urlManual.Trim(); Version = $verManual }
}




# --- Hacer respaldo antes de actualizar ---
function New-Respaldo {
    param([string]$VersionNueva)

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $destDir = Join-Path $RespDir "resp-actualizacion-v${VersionNueva}_$timestamp"
    
    # Crear carpetas
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    $worldsDst = Join-Path $destDir "worlds"
    New-Item -ItemType Directory -Path $worldsDst -Force | Out-Null

    Write-Host "  [+] Respaldando server.properties..." -ForegroundColor Cyan
    Copy-Item -Path (Join-Path $ServerDir "server.properties") -Destination $destDir -Force

    $worldsSrc = Join-Path $ServerDir "worlds" "LaMaldiciondelLag"
    if (Test-Path $worldsSrc) {
        Write-Host "  [+] Respaldando mundo (LaMaldiciondelLag)..." -ForegroundColor Cyan
        Copy-Item -Path "$worldsSrc\*" -Destination $worldsDst -Recurse -Force
    }

    Write-Host "  [OK] Respaldo guardado en: resp\$(Split-Path $destDir -Leaf)" -ForegroundColor Green
    return $destDir
}

# --- Descargar y aplicar actualizacion ---
function Install-Actualizacion {
    param([string]$Url, [string]$Version, [string]$BackupDir)

    $zipPath = Join-Path $env:TEMP "bedrock_server_$Version.zip"
    Write-Host "  [+] Descargando servidor v$Version..." -ForegroundColor Cyan
    Write-Host "      URL: $Url" -ForegroundColor DarkGray

    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url, $zipPath)
    }
    catch {
        Write-Host "  [ERROR] Fallo la descarga: $_" -ForegroundColor Red
        return $false
    }

    # Extraer a carpeta temporal
    Write-Host "  [+] Extrayendo servidor nuevo..." -ForegroundColor Cyan
    $tempExtract = Join-Path $env:TEMP "bedrock_extract_$Version"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force

    # Archivos del servidor que NUNCA se tocan (datos propios, no del servidor)
    $nuncaSobreescribir = @("resp", "version_actual.txt")

    # Copiar TODO lo del ZIP al servidor (instalacion limpia)
    Write-Host "  [+] Instalando archivos nuevos del servidor..." -ForegroundColor Cyan
    Get-ChildItem -Path $tempExtract | ForEach-Object {
        if ($nuncaSobreescribir -notcontains $_.Name) {
            $dest = Join-Path $ServerDir $_.Name
            if ($_.PSIsContainer) {
                Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
            }
            else {
                Copy-Item -Path $_.FullName -Destination $dest -Force
            }
        }
    }

    # Restaurar worlds y server.properties desde el respaldo (sobreescribe los del ZIP)
    Write-Host "  [+] Restaurando worlds/ y server.properties desde el respaldo..." -ForegroundColor Cyan

    $worldsBackup = Join-Path $BackupDir "worlds"
    $worldsDest = Join-Path $ServerDir "worlds" "LaMaldiciondelLag"
    if (Test-Path $worldsBackup) {
        if (-not (Test-Path $worldsDest)) { New-Item -ItemType Directory -Path $worldsDest -Force | Out-Null }
        Remove-Item "$worldsDest\*" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$worldsBackup\*" -Destination $worldsDest -Recurse -Force
        Write-Host "  [OK] Mundo (LaMaldiciondelLag) restaurado" -ForegroundColor Green
    }
    else {
        Write-Host "  [AVISO] No se encontro mundo en el respaldo: $BackupDir" -ForegroundColor DarkYellow
    }

    $propBackup = Join-Path $BackupDir "server.properties"
    $propDest = Join-Path $ServerDir "server.properties"
    if (Test-Path $propBackup) {
        Copy-Item -Path $propBackup -Destination $propDest -Force
        Write-Host "  [OK] server.properties restaurado" -ForegroundColor Green
    }
    else {
        Write-Host "  [AVISO] No se encontro server.properties en el respaldo: $BackupDir" -ForegroundColor DarkYellow
    }

    # Guardar nueva version
    $Version | Out-File -FilePath $VersionFile -Encoding utf8 -Force

    # Limpiar temporales
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "  [OK] Servidor actualizado a v$Version" -ForegroundColor Green
    return $true
}

# =========================================================
# MAIN
# =========================================================

Write-Host ""
Write-Host "--- Verificacion de Actualizaciones ---" -ForegroundColor Yellow

$versionActual = Get-VersionActual
Write-Host "  Version actual : $versionActual" -ForegroundColor White

$latest = Get-UltimaVersion -VersionActual $versionActual
if ($null -eq $latest) {
    Write-Host "  [AVISO] No se pudo verificar en linea. Continuando sin actualizar." -ForegroundColor DarkYellow
    return
}

Write-Host "  Version online : $($latest.Version)" -ForegroundColor White

# Comparar versiones correctamente (no como texto sino como numeros)
# Normaliza a 4 segmentos para que "1.26.3" == [1.26.3.0] sea menor que [1.26.3.1]
function ConvertTo-Version([string]$v) {
    $parts = $v -split '\.'
    while ($parts.Count -lt 4) { $parts += '0' }
    try { return [System.Version]($parts[0..3] -join '.') }
    catch { return [System.Version]"0.0.0.0" }
}

$verActualObj = ConvertTo-Version $versionActual
$verOnlineObj = ConvertTo-Version $latest.Version

if ($verOnlineObj -le $verActualObj -and -not $Forzar) {
    Write-Host "  [OK] El servidor ya esta actualizado!" -ForegroundColor Green
    Write-Host ""
    return
}


if ($Forzar) {
    Write-Host "  [MODO FORZADO] Actualizando de todas formas..." -ForegroundColor Magenta
}
else {
    Write-Host ""
    Write-Host "  Nueva version disponible: $($latest.Version)" -ForegroundColor Yellow
    $respuesta = Read-Host "  Deseas actualizar ahora? (S/N)"
    if ($respuesta -notmatch "^[sS]") {
        Write-Host "  Actualizacion omitida." -ForegroundColor DarkGray
        Write-Host ""
        return
    }
}

Write-Host ""
$backupDir = New-Respaldo -VersionNueva $versionActual
Install-Actualizacion -Url $latest.Url -Version $latest.Version -BackupDir $backupDir | Out-Null

Write-Host ""
Write-Host "--- Actualizacion completada ---" -ForegroundColor Green
Write-Host ""
