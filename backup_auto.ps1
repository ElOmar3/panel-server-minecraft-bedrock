# =============================================================
#  backup_auto.ps1 - Backup automatico del mundo (sin kick)
#  Puede ejecutarse como loop o llamarse desde tarea programada
# =============================================================

param(
    [switch]$Silencioso    # Suprime mensajes en consola cuando se corre en background
)

$ServerDir = $PSScriptRoot

$RespDir = Join-Path $ServerDir "resp"
$MaxBackups = 3   # Solo conservar los 3 ultimos backups automaticos

function Write-Log {
    param([string]$Msg, [string]$Color = "White")
    if (-not $Silencioso) {
        Write-Host $Msg -ForegroundColor $Color
    }
    $logFile = Join-Path $ServerDir "backup_log.txt"
    $linea = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Msg"
    Add-Content -Path $logFile -Value $linea -Encoding utf8
}

# ---- Enviar comando al servidor forzando el foco de manera segura ----
# ---- Enviar comando al servidor de forma robusta ----
function Send-ServerCommand {
    param([string]$Comando)
    
    # Asegurar que el caracter § sea el correcto independientemente de la codificacion
    $Comando = $Comando.Replace("Â§", "§")

    # 1. Intentar encontrar la ventana por titulo o por proceso
    $proc = Get-Process | Where-Object { 
        $_.MainWindowHandle -ne 0 -and 
        ($_.MainWindowTitle -match "MiServerMinecraft" -or $_.ProcessName -eq "bedrock_server" -or $_.MainWindowTitle -match "Bedrock Dedicated Server")
    } | Select-Object -First 1

    # 2. Si no se encontro, intentar buscar el proceso bedrock_server y ver si su padre tiene ventana
    if (-not $proc) {
        $bs = Get-Process -Name "bedrock_server" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bs) {
            # Intentar obtener el padre (usualmente cmd.exe)
            try {
                $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $($bs.Id)").ParentProcessId
                if ($parentPid) {
                    $parentProc = Get-Process -Id $parentPid -ErrorAction SilentlyContinue
                    if ($parentProc -and $parentProc.MainWindowHandle -ne 0) {
                        $proc = $parentProc
                    }
                }
            }
            catch {}
        }
    }

    if ($proc) {
        $code = @"
        using System;
        using System.Runtime.InteropServices;
        public class WinHkSys {
            [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
            [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr ProcessId);
            [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
            
            public static void ForceForeground(IntPtr hWnd) {
                IntPtr hFore = GetForegroundWindow();
                if (hFore == hWnd) return;
                uint foreThread = GetWindowThreadProcessId(hFore, IntPtr.Zero);
                uint appThread = GetWindowThreadProcessId(hWnd, IntPtr.Zero);
                if (foreThread != appThread) {
                    AttachThreadInput(foreThread, appThread, true);
                    SetForegroundWindow(hWnd);
                    ShowWindow(hWnd, 9); // SW_RESTORE
                    AttachThreadInput(foreThread, appThread, false);
                } else {
                    SetForegroundWindow(hWnd);
                    ShowWindow(hWnd, 9);
                }
            }
        }
"@
        if (-not ([System.Management.Automation.PSTypeName]'WinHkSys').Type) { Add-Type -TypeDefinition $code }
        
        Add-Type -AssemblyName System.Windows.Forms
        $wshell = New-Object -ComObject wscript.shell
        
        $ventanaOriginal = [WinHkSys]::GetForegroundWindow()
        
        # Preparar portapapeles
        try { [System.Windows.Forms.Clipboard]::SetText($Comando) } catch { 
            Write-Log "  [ERROR] No se pudo acceder al portapapeles." "Red"
            return $false 
        }

        # Traer al frente y enviar comandos
        [WinHkSys]::ForceForeground($proc.MainWindowHandle)
        Start-Sleep -Milliseconds 300
        
        # Enviar un ENTER extra por si la consola esta en modo seleccion (QuickEdit)
        $wshell.SendKeys("~") 
        Start-Sleep -Milliseconds 100
        
        # Pegar comando y ejecutar
        $wshell.SendKeys("^v~")
        Start-Sleep -Milliseconds 300
        
        # Devolver el foco si era otra ventana
        if ($ventanaOriginal -ne [IntPtr]::Zero -and $ventanaOriginal -ne $proc.MainWindowHandle) {
            [WinHkSys]::ForceForeground($ventanaOriginal)
        }
        
        try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
        return $true
    }
    
    Write-Log "  [ERROR] No se pudo encontrar la ventana del servidor para enviar el comando." "Red"
    return $false
}


function New-BackupAuto {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $destDir = Join-Path $RespDir "resp-$timestamp"

    Write-Log "--- Iniciando respaldo: $timestamp ---" "Cyan"
    
    # Crear carpeta principal del respaldo
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    
    # Crear subcarpeta 'worlds' dentro del respaldo
    $worldsDst = Join-Path $destDir "worlds"
    New-Item -ItemType Directory -Path $worldsDst -Force | Out-Null

    $propSrc = Join-Path $ServerDir "server.properties"
    
    # Obtener el nombre del mundo dinámicamente de server.properties
    $worldName = "Bedrock level"
    if (Test-Path $propSrc) {
        $levelNameLine = Get-Content $propSrc | Select-String -Pattern "^level-name=(.*)$"
        if ($levelNameLine) {
            $worldName = $levelNameLine.Matches[0].Groups[1].Value.Trim()
        }
    }
    
    $worldsSrc = Join-Path $ServerDir "worlds" $worldName
    
    # Verificar si el servidor esta activo (sin robar el foco)
    $serverActivo = [bool](Get-Process -Name "bedrock_server" -ErrorAction SilentlyContinue)

    # -------------------------------------------------------
    # MENSAJE 1 - "Iniciando Respaldo..."
    # -------------------------------------------------------
    if ($serverActivo) {
        $null = Send-ServerCommand "say §l§e >> Iniciando Respaldo..."
        Write-Log "  [Chat] Mensaje 1 enviado: Iniciando Respaldo..." "DarkGray"
    }

    # Iniciar copia de archivos en BACKGROUND
    $job = Start-Job -ScriptBlock {
        param($src, $dst, $prop, $destDir)
        # Copiar server.properties al directorio principal del respaldo
        if (Test-Path $prop) { Copy-Item -Path $prop -Destination $destDir -Force }
        # Copiar todo el CONTENIDO del mundo a la subcarpeta 'worlds' del respaldo
        if (Test-Path $src) { 
            Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force 
        }
    } -ArgumentList $worldsSrc, $worldsDst, $propSrc, $destDir

    # -------------------------------------------------------
    # ESPERAR ~10 seg
    # -------------------------------------------------------
    Start-Sleep -Seconds 10

    # MENSAJE 2 - "En progreso..."
    if ($serverActivo) {
        $null = Send-ServerCommand "say §l§b >> En progreso..."
        Write-Log "  [Chat] Mensaje 2 enviado: En progreso..." "DarkGray"
    }

    # Esperar a que el backup TERMINE
    Wait-Job $job | Out-Null
    Remove-Job $job -Force

    Write-Log "  [+] Archivos copiados a: $destDir" "Green"

    # -------------------------------------------------------
    # ESPERAR otros ~10 seg
    # -------------------------------------------------------
    Start-Sleep -Seconds 10

    # MENSAJE 3 - "Respaldo Finalizado. OK!"
    if ($serverActivo) {
        $null = Send-ServerCommand "say §l§a >> Respaldo Finalizado. OK!"
        Write-Log "  [Chat] Mensaje 3 enviado: Respaldo Finalizado." "Green"
    }

    Write-Log "  [OK] Respaldo guardado en: resp\resp-$timestamp" "Green"

    # --- Limpieza: guardar solo los ultimos $MaxBackups respaldos ---
    # Busca carpetas con prefijo "resp-"
    $todosResp = Get-ChildItem -Path $RespDir -Directory -Filter "resp-*" | Sort-Object CreationTime
    $exceso = $todosResp.Count - $MaxBackups
    if ($exceso -gt 0) {
        $aEliminar = $todosResp | Select-Object -First $exceso
        foreach ($dir in $aEliminar) {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  [Limpieza] Eliminado respaldo antiguo: $($dir.Name)" "DarkGray"
        }
    }

    Write-Log "--- Respaldo completado ---" "Cyan"
    Write-Log "" "White"
}

# Ejecutar backup inmediatamente al llamar el script
New-BackupAuto
