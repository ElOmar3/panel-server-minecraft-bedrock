# =============================================================
#  apagarserver.ps1 - Apaga el servidor con aviso a jugadores
#  Usa _bds_send.ps1 como helper para enviar comandos sin
#  corromper los handles de consola del proceso actual
# =============================================================



function Send-Cmd {
    param([string]$Comando)
    $Comando = $Comando.Replace("Â§", "§")
    $proc = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -eq "cmd" -and $_.MainWindowTitle -match "MiServerMinecraft" } | Select-Object -First 1
    if ($proc) {
        $code = @"
        using System;
        using System.Runtime.InteropServices;
        public class WinHkSys2 {
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
                    ShowWindow(hWnd, 9);
                    AttachThreadInput(foreThread, appThread, false);
                } else {
                    SetForegroundWindow(hWnd);
                    ShowWindow(hWnd, 9);
                }
            }
        }
"@
        if (-not ([System.Management.Automation.PSTypeName]'WinHkSys2').Type) { Add-Type -TypeDefinition $code }
        
        Add-Type -AssemblyName System.Windows.Forms
        $wshell = New-Object -ComObject wscript.shell
        
        $ventanaOriginal = [WinHkSys2]::GetForegroundWindow()
        
        try { [System.Windows.Forms.Clipboard]::SetText($Comando) } catch {}
        [WinHkSys2]::ForceForeground($proc.MainWindowHandle)
        Start-Sleep -Milliseconds 250
        
        $wshell.SendKeys("^v~")
        Start-Sleep -Milliseconds 250
        
        if ($ventanaOriginal -ne [IntPtr]::Zero -and $ventanaOriginal -ne $proc.MainWindowHandle) {
            [WinHkSys2]::ForceForeground($ventanaOriginal)
        }
        try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
        return $true
    }
    return $false
}

# ---- VERIFICAR QUE EL SERVIDOR ESTE CORRIENDO ----
$proc = Get-Process -Name "bedrock_server" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) {
    Write-Host "  [ERROR] El servidor no esta corriendo (bedrock_server.exe no encontrado)." -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "  Iniciando apagado con aviso de 60 segundos..." -ForegroundColor Yellow
Write-Host ""

# ---- AVISO A JUGADORES (neon) ----
Send-Cmd "say §l§c >> SERVIDOR CERRANDO EN 60 SEGUNDOS..." | Out-Null
Write-Host "  [Chat] Aviso 60s enviado." -ForegroundColor DarkGray

Start-Sleep -Seconds 30

Send-Cmd "say §l§e >> SERVIDOR CERRANDO EN 30 SEGUNDOS..." | Out-Null
Write-Host "  [Chat] Aviso 30s enviado." -ForegroundColor DarkGray

Start-Sleep -Seconds 20

Send-Cmd "say §l§e >> SERVIDOR CERRANDO EN 10 SEGUNDOS..." | Out-Null
Write-Host "  [Chat] Aviso 10s enviado." -ForegroundColor DarkGray

Start-Sleep -Seconds 5

Send-Cmd "say §l§c >> SERVIDOR CERRANDO EN 5 SEGUNDOS..." | Out-Null

Start-Sleep -Seconds 1
Send-Cmd "say §l§c >> 4..." | Out-Null
Start-Sleep -Seconds 1
Send-Cmd "say §l§c >> 3..." | Out-Null
Start-Sleep -Seconds 1
Send-Cmd "say §l§c >> 2..." | Out-Null
Start-Sleep -Seconds 1
Send-Cmd "say §l§c >> 1..." | Out-Null
Start-Sleep -Seconds 1

# ---- APAGAR EL SERVIDOR ----
Send-Cmd "say §l§4 >> SERVIDOR APAGADO. Hasta luego!" | Out-Null
Start-Sleep -Milliseconds 800
Send-Cmd "stop" | Out-Null

Write-Host "  [OK] Comando 'stop' enviado al servidor." -ForegroundColor Green
Write-Host ""