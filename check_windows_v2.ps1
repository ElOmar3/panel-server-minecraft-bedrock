# Muestra todos los procesos que tienen una ventana (MainWindowHandle != 0)
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object ProcessName, Id, MainWindowTitle | Format-Table -AutoSize

# Muestra cualquier proceso que tenga "Minecraft" o "Bedrock" en el nombre o titulo
Write-Host "`n--- Busqueda extendida (Procesos con Minecraft/Bedrock) ---"
Get-Process | Where-Object { $_.ProcessName -match "Minecraft|bedrock" -or $_.MainWindowTitle -match "Minecraft|bedrock|Server" } | Select-Object ProcessName, Id, MainWindowTitle | Format-Table -AutoSize
