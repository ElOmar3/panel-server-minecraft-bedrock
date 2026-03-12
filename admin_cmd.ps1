# =============================================================
#  admin_cmd.ps1 - Panel de Comandos Admin para Minecraft Bedrock
#  Requiere que el servidor este corriendo con titulo "MiServerMinecraft"
# =============================================================

$ServerTitle = "MiServerMinecraft"

function Send-ServerCommand {
    param([string]$Comando)
    
    # Asegurar que el caracter § sea el correcto
    $Comando = $Comando.Replace("Â§", "§")
    
    # 1. Intentar encontrar la ventana por titulo o por proceso
    $proc = Get-Process | Where-Object { 
        $_.MainWindowHandle -ne 0 -and 
        ($_.MainWindowTitle -match $ServerTitle -or $_.ProcessName -eq "bedrock_server" -or $_.MainWindowTitle -match "Bedrock Dedicated Server")
    } | Select-Object -First 1

    # 2. Si no se encontro, buscar via proceso bedrock_server
    if (-not $proc) {
        $bs = Get-Process -Name "bedrock_server" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bs) {
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
        public class WinHkSysAdmin {
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
        if (-not ([System.Management.Automation.PSTypeName]'WinHkSysAdmin').Type) { Add-Type -TypeDefinition $code }
        
        Add-Type -AssemblyName System.Windows.Forms
        $wshell = New-Object -ComObject wscript.shell
        
        $ventanaOriginal = [WinHkSysAdmin]::GetForegroundWindow()
        
        try { [System.Windows.Forms.Clipboard]::SetText($Comando) } catch { return $false }
        
        [WinHkSysAdmin]::ForceForeground($proc.MainWindowHandle)
        Start-Sleep -Milliseconds 300
        
        # Wake up console
        $wshell.SendKeys("~") 
        Start-Sleep -Milliseconds 100
        
        $wshell.SendKeys("^v~")
        Start-Sleep -Milliseconds 300
        
        if ($ventanaOriginal -ne [IntPtr]::Zero -and $ventanaOriginal -ne $proc.MainWindowHandle) {
            [WinHkSysAdmin]::ForceForeground($ventanaOriginal)
        }
        try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
        return $true
    }
    return $false
}

function Invoke-Cmd {
    param([string]$Cmd, [string]$Desc)
    Write-Host ""
    Write-Host "  Ejecutando: $Cmd" -ForegroundColor DarkGray
    $ok = Send-ServerCommand $Cmd
    if ($ok) {
        Write-Host "  [OK] $Desc enviado al servidor." -ForegroundColor Green
    }
    else {
        Write-Host "  [ERROR] No se encontro la ventana '$ServerTitle'. El servidor esta apagado?" -ForegroundColor Red
    }
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Magenta
    Write-Host "     PANEL ADMIN - MINECRAFT BEDROCK         " -ForegroundColor Magenta
    Write-Host "  ============================================" -ForegroundColor Magenta
    Write-Host "   1)  Ver jugadores online (list)           " -ForegroundColor White
    Write-Host "   2)  Dar OP a jugador                      " -ForegroundColor White
    Write-Host "   3)  Quitar OP a jugador                   " -ForegroundColor White
    Write-Host "   4)  Kick a jugador                        " -ForegroundColor White
    Write-Host "   5)  Banear jugador                        " -ForegroundColor White
    Write-Host "   6)  Desbanear jugador                     " -ForegroundColor White
    Write-Host "   7)  Mensaje global (say)                  " -ForegroundColor White
    Write-Host "   8)  Dar item a jugador (give)             " -ForegroundColor White
    Write-Host "   9)  Teleportar jugador                    " -ForegroundColor White
    Write-Host "   10) Cambiar modo de juego                 " -ForegroundColor White
    Write-Host "   11) Cambiar clima                         " -ForegroundColor White
    Write-Host "   12) Cambiar hora del dia                  " -ForegroundColor White
    Write-Host "   13) Backup manual inmediato               " -ForegroundColor Yellow
    Write-Host "   14) Apagar servidor con aviso             " -ForegroundColor Red
    Write-Host "   15) Comando personalizado                 " -ForegroundColor Cyan
    Write-Host "   ----------------------------------------   " -ForegroundColor DarkGray
    Write-Host "   16) CERRAR TODO (server + playit + ventanas)" -ForegroundColor Red
    Write-Host "   0)  Salir del panel                       " -ForegroundColor DarkGray
    Write-Host "  ============================================" -ForegroundColor Magenta
    Write-Host ""
}

# Bucle principal
do {
    Show-Menu
    $opcion = Read-Host "  Selecciona una opcion"

    switch ($opcion) {
        "1" { Invoke-Cmd "list" "Peticion de lista de jugadores" }
        
        "2" {
            $jugador = Read-Host "  Nombre del jugador"
            if ($jugador) { Invoke-Cmd "op `"$jugador`"" "OP otorgado a $jugador" }
        }

        "3" {
            $jugador = Read-Host "  Nombre del jugador"
            if ($jugador) { Invoke-Cmd "deop `"$jugador`"" "OP quitado a $jugador" }
        }

        "4" {
            $jugador = Read-Host "  Nombre del jugador"
            $razon = Read-Host "  Razon (opcional)"
            if ($jugador) { Invoke-Cmd "kick `"$jugador`" $razon" "Kick enviado a $jugador" }
        }

        "5" {
            $jugador = Read-Host "  Nombre del jugador"
            if ($jugador) {
                # Bedrock no tiene 'ban' nativo por nombre, usualmente requiere Add-ons o usar la blacklist de xbox live
                # Pero en BDS modificado o con BDSX funciona. Si es vanilla, se suele usar kick y whitelist.
                # Lo dejamos como comando 'kick' temporal o 'ban' si se usa un mod.
                Invoke-Cmd "kick `"$jugador`" BANEADO" "Jugador baneado (kick)"
            }
        }

        "6" {
            Write-Host "  [AVISO] En Bedrock Vanilla el desbaneo se gestiona en allowlist.json o permissions.json" -ForegroundColor Yellow
        }

        "7" {
            $msg = Read-Host "  Mensaje"
            if ($msg) { Invoke-Cmd "say §a[Admin]§r $msg" "Mensaje global enviado" }
        }

        "8" {
            $jugador = Read-Host "  Nombre del jugador o @a"
            $item = Read-Host "  ID del item (ej. diamond)"
            $cant = Read-Host "  Cantidad"
            if ($jugador -and $item) {
                if (-not $cant) { $cant = 1 }
                Invoke-Cmd "give `"$jugador`" $item $cant" "$cant x $item dado a $jugador"
            }
        }

        "9" {
            $origen = Read-Host "  Jugador a teleportar"
            $destino = Read-Host "  Destino (Jugador o X Y Z)"
            if ($origen -and $destino) { Invoke-Cmd "tp `"$origen`" $destino" "Teleport de $origen a $destino" }
        }

        "10" {
            $jugador = Read-Host "  Nombre del jugador o @a"
            Write-Host "  Modos: [0] Survival  [1] Creative  [2] Adventure  [3] Spectator" -ForegroundColor Cyan
            $modo = Read-Host "  Modo (0-3 o inicial)"
            if ($jugador -and $modo) { Invoke-Cmd "gamemode $modo `"$jugador`"" "Gamemode cambiado para $jugador" }
        }

        "11" {
            Write-Host "  Clima: [1] Clear  [2] Rain  [3] Thunder" -ForegroundColor Cyan
            $clima = Read-Host "  Opcion"
            $duracion = Read-Host "  Duracion en segundos (Enter = 3600)"
            if (-not $duracion) { $duracion = "3600" }
            $climas = @{ "1" = "clear"; "2" = "rain"; "3" = "thunder" }
            if ($climas.ContainsKey($clima)) {
                Invoke-Cmd "weather $($climas[$clima]) $duracion" "Clima cambiado a $($climas[$clima])"
            }
        }

        "12" {
            Write-Host "  Hora: [1] Amanecer (1000)  [2] Mediodia (6000)  [3] Noche (13000)  [4] Personalizada" -ForegroundColor Cyan
            $hora = Read-Host "  Opcion"
            $horas = @{ "1" = "1000"; "2" = "6000"; "3" = "13000" }
            if ($horas.ContainsKey($hora)) {
                Invoke-Cmd "time set $($horas[$hora])" "Hora cambiada"
            }
            elseif ($hora -eq "4") {
                $ticks = Read-Host "  Ticks (0-24000)"
                if ($ticks) { Invoke-Cmd "time set $ticks" "Hora cambiada a $ticks ticks" }
            }
        }

        "13" {
            Write-Host ""
            Write-Host "  Iniciando backup manual..." -ForegroundColor Yellow
            $backupScript = Join-Path $PSScriptRoot "backup_auto.ps1"
            if (Test-Path $backupScript) {
                # Lanzar en proceso separado sin -NoExit para que se cierre al terminar
                Start-Process powershell.exe -ArgumentList @(
                    "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-File", "`"$backupScript`""
                ) -WindowStyle Normal
                Write-Host "  [OK] Backup iniciado en ventana separada." -ForegroundColor Green
            }
            else {
                Write-Host "  [ERROR] No se encontro backup_auto.ps1" -ForegroundColor Red
            }
        }

        "14" {
            Write-Host ""
            Write-Host "  ATENCION: Esto apagara el servidor con aviso a los jugadores." -ForegroundColor Red
            $confirmar = Read-Host "  Confirmas? (S/N)"
            if ($confirmar -match "^[sS]") {
                $apagarScript = Join-Path $PSScriptRoot "apagarserver.ps1"
                if (Test-Path $apagarScript) {
                    # Lanzar en proceso separado sin -NoExit para que se cierre al terminar
                    Start-Process powershell.exe -ArgumentList @(
                        "-NoProfile", "-ExecutionPolicy", "Bypass",
                        "-File", "`"$apagarScript`""
                    ) -WindowStyle Normal
                    Write-Host "  [OK] Apagado iniciado. Revisa la ventana que se abrio." -ForegroundColor Green
                }
                else {
                    Write-Host "  [ERROR] No se encontro apagarserver.ps1" -ForegroundColor Red
                }
            }
        }

        "15" {
            $cmd = Read-Host "  Escribe el comando completo (sin /)"
            if ($cmd) { Invoke-Cmd $cmd "Comando personalizado enviado" }
        }

        "16" {
            Write-Host ""
            Write-Host "  ATENCION: Esto cerrara TODAS las ventanas del servidor." -ForegroundColor Red
            Write-Host "  Se cerrara: bedrock_server, playit, ventana de inicio." -ForegroundColor DarkYellow
            $confirmar = Read-Host "  Confirmas? (S/N)"
            if ($confirmar -match "^[sS]") {
                Write-Host ""

                # 1. Enviar stop al servidor (apagado limpio)
                Write-Host "  [1/4] Enviando 'stop' al servidor..." -ForegroundColor Cyan
                Send-ServerCommand "stop" | Out-Null
                Start-Sleep -Seconds 4

                # 2. Forzar cierre de bedrock_server.exe si sigue corriendo
                Write-Host "  [2/4] Cerrando bedrock_server.exe..." -ForegroundColor Cyan
                Get-Process -Name "bedrock_server" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

                # 3. Cerrar PlayitGG
                Write-Host "  [3/4] Cerrando PlayitGG..." -ForegroundColor Cyan
                Get-Process -Name "playit" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

                # 4. Cerrar la ventana de inicio (titulo: "Lanzador - Minecraft Bedrock")
                Write-Host "  [4/4] Cerrando ventana de inicio..." -ForegroundColor Cyan
                $miPid = $PID  # PID del panel admin (no lo matamos todavia)
                Get-Process -Name "cmd", "powershell" -ErrorAction SilentlyContinue | Where-Object {
                    $_.Id -ne $miPid -and
                    $_.MainWindowTitle -ne $null -and
                    $_.MainWindowTitle -match "Lanzador|Minecraft Bedrock|iniciar|MiServer"
                } | Stop-Process -Force -ErrorAction SilentlyContinue

                Write-Host ""
                Write-Host "  [OK] Todo cerrado. Chao!" -ForegroundColor Green
                Write-Host ""
                Start-Sleep -Seconds 1

                # Forzar cierre del panel admin aunque haya sido lanzado con -NoExit
                [System.Environment]::Exit(0)
            }
        }

        "0" {
            Write-Host ""
            Write-Host "  Saliendo del panel admin. El servidor sigue corriendo." -ForegroundColor DarkGray
            Write-Host ""
        }

        default {
            Write-Host "  [!] Opcion no valida." -ForegroundColor Yellow
        }
    }

    if ($opcion -ne "0") {
        Write-Host ""
        Write-Host "  Presiona Enter para volver al menu..." -ForegroundColor DarkGray
        Read-Host | Out-Null
    }

} while ($opcion -ne "0")

