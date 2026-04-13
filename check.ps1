Write-Output "source\Debug\cjsond.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\cjson\source\Debug\cjsond.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "source\Release\cjson.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\cjson\source\Release\cjson.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "install\lib\cjsond.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install\lib\cjsond.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "install\lib\cjson.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install\lib\cjson.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "source\Debug\ccronexprd.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\ccronexpr\source\Debug\ccronexprd.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "source\Release\ccronexpr.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\ccronexpr\source\Release\ccronexpr.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "install\lib\ccronexprd.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install\lib\ccronexprd.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
Write-Output "install\lib\ccronexpr.lib"
dumpbin /directives C:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install\lib\ccronexpr.lib | Select-String "DEFAULTLIB" | ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique

