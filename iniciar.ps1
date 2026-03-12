# =============================================================
#  iniciar.ps1 - Inicio del Servidor Minecraft Bedrock
#  Lanza bedrock_server.exe + PlayitGG + Backup automatico
# =============================================================

# ---- CONFIGURACION (ajusta si es necesario) ----
$ServerDir = $PSScriptRoot
$ServerTitle = "MiServerMinecraft"
$PlayitPath = "C:\Program Files\playit_gg\bin\playit.exe"   # Ruta de PlayitGG
$RespDir = Join-Path $ServerDir "resp"

# Intervalo de backup automatico (en segundos). 1800 = 30 minutos
$BackupIntervalSeconds = 1800
# -------------------------------------------------------

Set-Location $ServerDir

# =====================================================
# FUNCION: Verificar integridad del mundo vs respaldo
# =====================================================
function Test-IntegridadMundo {
    $targetWorldDir = Join-Path $ServerDir "worlds" "LaMaldiciondelLag"

    Write-Host ""
    Write-Host "  [INTEGRIDAD] Verificando mundo actual contra respaldo..." -ForegroundColor Yellow

    # --- Buscar el respaldo mas reciente en resp/ ---
    $backupReciente = $null
    if (Test-Path $RespDir) {
        $backupReciente = Get-ChildItem -Path $RespDir -Directory |
        Where-Object { $_.Name -match "^resp-" } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    }

    # --- Caso 1: No existe la carpeta del mundo en el servidor ---
    if (-not (Test-Path $targetWorldDir)) {
        Write-Host "  [ALERTA] La carpeta del mundo 'worlds/LaMaldiciondelLag' NO EXISTE!" -ForegroundColor Red
        if ($backupReciente) {
            Write-Host "  Respaldo encontrado: $($backupReciente.Name). Restaurando..." -ForegroundColor Cyan
            Restore-DesdBackup (Join-Path $RespDir $backupReciente.Name)
        }
        else {
            Write-Host "  [AVISO] Sin respaldo disponible. El server generara un mundo nuevo." -ForegroundColor DarkYellow
        }
        return
    }

    # --- Caso 2: No hay respaldo disponible aun ---
    if (-not $backupReciente) {
        Write-Host "  [OK] Sin respaldo previo todavia (primera ejecucion)." -ForegroundColor DarkGray
        return
    }

    # --- Verificar que el respaldo tenga worlds/ ---
    $backupRuta = Join-Path $RespDir $backupReciente.Name
    $backupWorldsDir = Join-Path $backupRuta "worlds"

    if (-not (Test-Path $backupWorldsDir)) {
        Write-Host "  [AVISO] El respaldo mas reciente ($($backupReciente.Name)) no tiene carpeta 'worlds/'" -ForegroundColor DarkYellow
        return
    }

    # --- Comparar tamanio actual vs respaldo (en bytes) ---
    $bytesActual = (Get-ChildItem -Path $targetWorldDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $bytesActual) { $bytesActual = 0 }

    $bytesBackup = (Get-ChildItem -Path $backupWorldsDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $bytesBackup) { $bytesBackup = 0 }

    $mbActual = [Math]::Round(($bytesActual / 1MB), 2)
    $mbBackup = [Math]::Round(($bytesBackup / 1MB), 2)

    Write-Host "  Mundo actual ($targetWorldDir): $mbActual MB" -ForegroundColor White
    Write-Host "  Respaldo ($($backupReciente.Name)): $mbBackup MB" -ForegroundColor DarkGray

    # --- Lógica de restauración automática si es más pequeño ---
    if ($bytesActual -lt $bytesBackup) {
        $dif = $bytesBackup - $bytesActual
        Write-Host ""
        Write-Host "  [ALERTA] El mundo actual es MAS PEQUEÑO que el respaldo ($dif bytes de diferencia)." -ForegroundColor Red
        Write-Host "  Delegando respaldo al original (restaurando)..." -ForegroundColor Cyan
        Restore-DesdBackup $backupRuta
    }
    else {
        Write-Host "  [OK] El mundo actual tiene un tamaño adecuado. Todo bien." -ForegroundColor Green
    }
}

function Restore-DesdBackup {
    param([string]$BackupPath)
    $targetWorldDir = Join-Path $ServerDir "worlds" "LaMaldiciondelLag"
    $propFile = Join-Path $ServerDir "server.properties"

    Write-Host ""
    Write-Host "  Restaurando desde: $BackupPath" -ForegroundColor Cyan

    # Restaurar contenido del mundo
    $backupWorldsContent = Join-Path $BackupPath "worlds"
    if (Test-Path $backupWorldsContent) {
        if (-not (Test-Path $targetWorldDir)) { New-Item -ItemType Directory -Path $targetWorldDir -Force | Out-Null }
        
        # Limpiar mundo actual antes de pegar (para evitar mezcla de archivos corruptos)
        Remove-Item "$targetWorldDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Copiar contenido desde el respaldo
        Copy-Item -Path "$backupWorldsContent\*" -Destination $targetWorldDir -Recurse -Force
        Write-Host "  [OK] Contenido de 'worlds' restaurado en LaMaldiciondelLag." -ForegroundColor Green
    }

    # Restaurar server.properties
    $backupProp = Join-Path $BackupPath "server.properties"
    if (Test-Path $backupProp) {
        Copy-Item -Path $backupProp -Destination $propFile -Force
        Write-Host "  [OK] server.properties restaurado." -ForegroundColor Green
    }

    Write-Host "  Restauracion completada." -ForegroundColor Green
    Write-Host ""
}

# =====================================================

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  SERVIDOR MINECRAFT BEDROCK - INICIO" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 0. Verificar integridad del mundo vs respaldo
Test-IntegridadMundo
Write-Host ""

# 1. Verificar actualizaciones antes de iniciar
Write-Host "[INFO] Verificando actualizaciones..." -ForegroundColor Yellow
$ActualizarScript = Join-Path $ServerDir "actualizar.ps1"
if (Test-Path $ActualizarScript) {
    & $ActualizarScript
}
else {
    Write-Host "[AVISO] No se encontro actualizar.ps1, omitiendo verificacion." -ForegroundColor DarkYellow
}

Write-Host ""

# 2. Iniciar bedrock_server.exe en su propia ventana
Write-Host "[INFO] Iniciando Bedrock Server..." -ForegroundColor Green
$BedrockArgs = @{
    FilePath         = "cmd.exe"
    ArgumentList     = "/c title $ServerTitle && bedrock_server.exe"
    WorkingDirectory = $ServerDir
    WindowStyle      = "Normal"
}
Start-Process @BedrockArgs

Start-Sleep -Seconds 3

# 3. Iniciar PlayitGG
if (Test-Path $PlayitPath) {
    Write-Host "[INFO] Iniciando PlayitGG..." -ForegroundColor Green
    Start-Process -FilePath $PlayitPath
}
else {
    Write-Host "[AVISO] No se encontro PlayitGG en: $PlayitPath" -ForegroundColor DarkYellow
    Write-Host "        Edita la variable `$PlayitPath en iniciar.ps1" -ForegroundColor DarkYellow
}

Start-Sleep -Seconds 3

# 4. Iniciar backup automatico en segundo plano (loop interactivo cada 30 min)
Write-Host "[INFO] Iniciando servicio de backup automatico (cada $($BackupIntervalSeconds / 60) minutos)..." -ForegroundColor Green
$BackupScript = Join-Path $ServerDir "backup_auto.ps1"

if (Test-Path $BackupScript) {
    # Usamos Start-Process en lugar de Start-Job para que tenga acceso a la sesion interactiva (necesario para SendKeys)
    $BackupProc = Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", "while(`$true){ Start-Sleep -Seconds $BackupIntervalSeconds; & '$BackupScript' -Silencioso }"
    ) -WindowStyle Hidden -PassThru

    Write-Host "[OK] Backup automatico activo (PID: $($BackupProc.Id))" -ForegroundColor Green
}
else {
    Write-Host "[AVISO] No se encontro backup_auto.ps1" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  SERVIDOR INICIADO CORRECTAMENTE" -ForegroundColor Cyan
Write-Host "  Cierra esta ventana para detener el" -ForegroundColor Cyan
Write-Host "  backup automatico en segundo plano." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Presiona Enter para abrir el Panel Admin (o cierra esta ventana para dejarlo corriendo)..." -ForegroundColor White
Read-Host | Out-Null

# 5. Abrir panel admin en ventana separada
$AdminScript = Join-Path $ServerDir "admin_cmd.ps1"
if (Test-Path $AdminScript) {
    Write-Host "[INFO] Abriendo Panel Admin en ventana separada..." -ForegroundColor Cyan
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-Command", "& '$AdminScript'"
    ) -WindowStyle Normal
    Write-Host "[OK] Panel Admin abierto." -ForegroundColor Green
}
else {
    Write-Host "[AVISO] No se encontro admin_cmd.ps1" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "  Esta ventana mantiene el backup automatico activo." -ForegroundColor DarkGray
Write-Host "  Cierra esta ventana solo cuando quieras apagar el servidor." -ForegroundColor DarkGray
Write-Host ""

