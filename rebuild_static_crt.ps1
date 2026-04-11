# Real-Time SDK: Complete Static CRT Rebuild Script
# This script performs a full clean rebuild with static CRT (/MT) for all externals and SDK libraries
# For Visual Studio 2022, x64, Release_MD configuration

param(
    [switch]$SkipClean = $false,
    [switch]$SkipExternals = $false,
    [switch]$VerifyOnly = $false
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Configuration
# ============================================================================

$REPO_ROOT = "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK"
$CMAKE = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$MSBUILD = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"
$DUMPBIN = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
$LINK = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-CRT {
    param(
        [string]$LibPath,
        [string]$LibName
    )
    
    if (-not (Test-Path $LibPath)) {
        Write-Warning-Custom "$LibName not found at $LibPath"
        return $false
    }
    
    $crtCheck = & $DUMPBIN /directives $LibPath 2>$null | Select-String "DEFAULTLIB:(LIBCMT|MSVCRT)"
    
    if (-not $crtCheck) {
        Write-Host "  $LibName CRT check: No CRT directives (likely import lib)" -ForegroundColor Gray
        return $true
    }
    
    # Determine if this is a debug or release library based on name
    $isDebug = $LibName -match "d\.lib$"
    $expectedCRT = if ($isDebug) { "LIBCMTD" } else { "LIBCMT" }
    
    # Check for mixed CRT by looking for both static and dynamic
    $hasLibcmt = $crtCheck | Where-Object { $_ -match "LIBCMT" }
    $hasMsvcrt = $crtCheck | Where-Object { $_ -match "MSVCRT" }
    
    Write-Host "  $LibName CRT check:" -NoNewline
    
    if ($hasLibcmt -and $hasMsvcrt) {
        Write-Host " [ERROR] MIXED CRT" -ForegroundColor Red
        $libcmtCount = ($hasLibcmt | Measure-Object).Count
        $msvcrtCount = ($hasMsvcrt | Measure-Object).Count
        Write-Host "      LIBCMT*: $libcmtCount objects" -ForegroundColor Yellow
        Write-Host "      MSVCRT*: $msvcrtCount objects" -ForegroundColor Yellow
        return $false
    }
    elseif ($hasLibcmt) {
        # Check if it matches the expected CRT for debug/release
        $crtMatches = $crtCheck | Select-Object -First 1 | Out-String
        if ($crtMatches -match $expectedCRT) {
            $count = ($hasLibcmt | Measure-Object).Count
            Write-Host " [OK] Static CRT ($expectedCRT) - $count objects" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host " [WARN] Wrong CRT (expected $expectedCRT)" -ForegroundColor Yellow
            return $false
        }
    }
    elseif ($hasMsvcrt) {
        $count = ($hasMsvcrt | Measure-Object).Count
        $dynamicCRT = if ($isDebug) { "MSVCRTD" } else { "MSVCRT" }
        Write-Host " [ERROR] Dynamic CRT ($dynamicCRT) - $count objects" -ForegroundColor Red
        return $false
    }
    else {
        Write-Host " [WARN] Unknown CRT" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================================
# Step 1: Clean Previous Artifacts
# ============================================================================

if (-not $SkipClean -and -not $VerifyOnly) {
    Write-Step "Step 1: Cleaning Previous Artifacts"
    
    cd $REPO_ROOT
    
    # Helper function to remove directory with retry logic (handles antivirus locks)
    function Remove-DirectoryWithRetry {
        param(
            [string]$Path,
            [int]$MaxRetries = 3,
            [int]$DelaySeconds = 2
        )
        
        if (-not (Test-Path $Path)) {
            return $true
        }
        
        for ($i = 1; $i -le $MaxRetries; $i++) {
            try {
                Write-Host "Removing $Path (attempt $i/$MaxRetries)..."
                Remove-Item -Recurse -Force $Path -ErrorAction Stop
                Write-Host "  Successfully removed $Path" -ForegroundColor Green
                return $true
            }
            catch {
                if ($i -lt $MaxRetries) {
                    Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "  Waiting ${DelaySeconds}s for file locks to clear..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $DelaySeconds
                }
                else {
                    Write-Host "  ERROR: Failed to remove $Path after $MaxRetries attempts" -ForegroundColor Red
                    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "" -ForegroundColor Yellow
                    Write-Host "  POSSIBLE CAUSES:" -ForegroundColor Yellow
                    Write-Host "  - Antivirus/Windows Defender scanning the directory" -ForegroundColor Yellow
                    Write-Host "  - Files open in another application" -ForegroundColor Yellow
                    Write-Host "  - Insufficient permissions" -ForegroundColor Yellow
                    Write-Host "" -ForegroundColor Yellow
                    Write-Host "  SOLUTIONS:" -ForegroundColor Yellow
                    Write-Host "  1. Add this folder to Windows Defender exclusions:" -ForegroundColor Yellow
                    Write-Host "     $REPO_ROOT\external\BUILD" -ForegroundColor Cyan
                    Write-Host "  2. Close any applications that may have files open" -ForegroundColor Yellow
                    Write-Host "  3. Run this script as Administrator" -ForegroundColor Yellow
                    Write-Host "  4. Manually delete the directory and re-run" -ForegroundColor Yellow
                    Write-Host ""
                    return $false
                }
            }
        }
    }
    
    Write-Host "Removing build directory..."
    $success1 = Remove-DirectoryWithRetry "build"
    
    Write-Host "Removing external builds..."
    $success2 = Remove-DirectoryWithRetry "external\BUILD"
    
    Write-Host "Removing install directory (to force rebuild with static CRT)..."
    $success3 = Remove-DirectoryWithRetry "install"
    
    if (-not ($success1 -and $success2 -and $success3)) {
        Write-Error-Custom "Failed to clean all directories. See errors above."
        exit 1
    }
    
    Write-Success "All artifacts cleaned"
}

# ============================================================================
# Step 2: Generate VS2022 Solution
# ============================================================================

if (-not $VerifyOnly) {
    Write-Step "Step 2: Generating VS2022 Solution with CMake"
    
    cd $REPO_ROOT
    
    if (-not (Test-Path "build")) {
        mkdir "build" | Out-Null
    }
    
    cd "build"
    
    Write-Host "Running CMake configuration with static CRT enforcement..."
    Write-Host "  Debug builds will use: MultiThreadedDebug (/MTd -> LIBCMTD)" -ForegroundColor Gray
    Write-Host "  Release builds will use: MultiThreaded (/MT -> LIBCMT)" -ForegroundColor Gray
    Write-Host "  External libraries will build in: $REPO_ROOT\external\BUILD" -ForegroundColor Gray
    Write-Host "  Install directory: $REPO_ROOT\install" -ForegroundColor Gray
    
    & $CMAKE `
        -G "Visual Studio 17 2022" -A x64 `
        -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
        -DCMAKE_MSVC_RUNTIME_LIBRARY="`$<`$<CONFIG:Debug_Mdd>:MultiThreadedDebug>`$<`$<CONFIG:Debug>:MultiThreadedDebug>`$<`$<CONFIG:Release_MD>:MultiThreaded>`$<`$<CONFIG:Release>:MultiThreaded>" `
        -Dlibxml2_USE_INSTALLED:BOOL=OFF `
        -DRCDEV_EXTERNAL_BINARY_PREFIX:PATH="$REPO_ROOT" `
        -DRCDEV_EXTERNAL_INSTALL_PREFIX:PATH="$REPO_ROOT\install" `
        -DBUILD_RTSDK-BINARYPACK:BOOL=OFF `
        -DRTSDK_OPT_BUILD_ETA_EMA_LIBRARIES:BOOL=ON `
        -DBUILD_UNIT_TESTS:BOOL=OFF `
        -DBUILD_ETA_EXAMPLES:BOOL=OFF `
        -DBUILD_EMA_EXAMPLES:BOOL=OFF `
        -DBUILD_EMA_DOXYGEN:BOOL=OFF `
        -DBUILD_ETA_TRAINING:BOOL=OFF `
        -DBUILD_ETA_PERFTOOLS:BOOL=OFF `
        ..
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "CMake configuration failed"
        exit 1
    }
    
    Write-Success "VS2022 solution generated"
    cd $REPO_ROOT
    
    # Verify external directory location
    Write-Host "`nVerifying external library locations..." -ForegroundColor Cyan
    if (Test-Path "external\BUILD") {
        Write-Host "  ✓ Externals built in: $REPO_ROOT\external\BUILD" -ForegroundColor Green
    } elseif (Test-Path "build\external") {
        Write-Host "  ✓ Externals built in: $REPO_ROOT\build\external" -ForegroundColor Green
    } elseif (Test-Path "build\internal") {
        Write-Host "  ⚠ WARNING: Externals built in unexpected location: $REPO_ROOT\build\internal" -ForegroundColor Yellow
        Write-Host "  This may be due to cached CMake variables from a previous build." -ForegroundColor Yellow
        Write-Host "  Consider cleaning CMakeCache.txt and re-running." -ForegroundColor Yellow
    } else {
        Write-Host "  ⚠ WARNING: Could not locate external build directory" -ForegroundColor Yellow
    }
}

# ============================================================================
# Step 3: Force Rebuild Key Externals with Static CRT (if needed)
# ============================================================================

if (-not $SkipExternals -and -not $VerifyOnly) {
    Write-Step "Step 3: Force Rebuilding Key Externals with Static CRT (if needed)"
    
    cd $REPO_ROOT
    
    # Rebuild zlib with static CRT
    Write-Host "`nRebuilding zlib..."
    $zlibSource = "external\BUILD\zlib\source"
    if (Test-Path $zlibSource) {
        cd $zlibSource
        Remove-Item "CMakeCache.txt" -ErrorAction SilentlyContinue
        Remove-Item -Recurse "CMakeFiles" -ErrorAction SilentlyContinue
        
        & $CMAKE `
            -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
            -DCMAKE_MSVC_RUNTIME_LIBRARY="$<$<CONFIG:Debug>:MultiThreadedDebug>$<$<CONFIG:Release>:MultiThreaded>" `
            -DBUILD_SHARED_LIBS=OFF `
            -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
            .
        
        & $CMAKE --build . --config Release
        & $CMAKE --build . --config Debug
        
        # Copy to install
        if (-not (Test-Path "$REPO_ROOT\install\lib")) {
            mkdir "$REPO_ROOT\install\lib" -Force | Out-Null
        }
        Copy-Item "Release\zlib.lib" "$REPO_ROOT\install\lib\zlib.lib" -Force
        Copy-Item "Debug\zlibd.lib" "$REPO_ROOT\install\lib\zlibd.lib" -Force
        
        Write-Success "zlib rebuilt"
        cd $REPO_ROOT
    }
    
    # Rebuild lz4 with static CRT
    Write-Host "`nRebuilding lz4..."
    $lz4Source = "external\BUILD\lz4\source\build\cmake"
    if (Test-Path $lz4Source) {
        cd $lz4Source
        Remove-Item "CMakeCache.txt" -ErrorAction SilentlyContinue
        Remove-Item -Recurse "CMakeFiles" -ErrorAction SilentlyContinue
        
        & $CMAKE `
            -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
            -DCMAKE_MSVC_RUNTIME_LIBRARY="$<$<CONFIG:Debug>:MultiThreadedDebug>$<$<CONFIG:Release>:MultiThreaded>" `
            -DBUILD_SHARED_LIBS=OFF `
            -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
            -DLZ4_BUILD_CLI=OFF `
            .
        
        & $CMAKE --build . --config Release
        & $CMAKE --build . --config Debug
        
        # Copy to install
        Copy-Item "Release\lz4.lib" "$REPO_ROOT\install\lib\lz4.lib" -Force
        Copy-Item "Debug\lz4.lib" "$REPO_ROOT\install\lib\lz4d.lib" -Force
        
        Write-Success "lz4 rebuilt"
        cd $REPO_ROOT
    }
    
    # Rebuild cjson with static CRT (reconfigure required)
    Write-Host "`nRebuilding cjson..."
    $cjsonSource = "external\BUILD\cjson\source"
    if (Test-Path $cjsonSource) {
        cd $cjsonSource
        Remove-Item "CMakeCache.txt" -ErrorAction SilentlyContinue
        Remove-Item -Recurse "CMakeFiles" -ErrorAction SilentlyContinue
        
        & $CMAKE `
            -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
            -DCMAKE_MSVC_RUNTIME_LIBRARY="`$<`$<CONFIG:Debug>:MultiThreadedDebug>`$<`$<CONFIG:Release>:MultiThreaded>" `
            -DBUILD_SHARED_LIBS=OFF `
            -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
            .
        
        & $CMAKE --build . --config Release
        & $CMAKE --build . --config Debug
        & $CMAKE --install . --config Release
        & $CMAKE --install . --config Debug
        
        Write-Success "cjson rebuilt"
        cd $REPO_ROOT
    }
    
    # Rebuild ccronexpr with static CRT (reconfigure required)
    Write-Host "`nRebuilding ccronexpr..."
    $ccronSource = "external\BUILD\ccronexpr\source"
    if (Test-Path $ccronSource) {
        cd $ccronSource
        Remove-Item "CMakeCache.txt" -ErrorAction SilentlyContinue
        Remove-Item -Recurse "CMakeFiles" -ErrorAction SilentlyContinue
        
        & $CMAKE `
            -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
            -DCMAKE_MSVC_RUNTIME_LIBRARY="`$<`$<CONFIG:Debug>:MultiThreadedDebug>`$<`$<CONFIG:Release>:MultiThreaded>" `
            -DBUILD_SHARED_LIBS=OFF `
            -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
            .
        
        & $CMAKE --build . --config Release
        & $CMAKE --build . --config Debug
        & $CMAKE --install . --config Release
        & $CMAKE --install . --config Debug
        
        Write-Success "ccronexpr rebuilt"
        cd $REPO_ROOT
    }
    
    # Rebuild l8w8jwt with static CRT (reconfigure required)
    Write-Host "`nRebuilding l8w8jwt..."
    $l8w8jwtSource = "external\BUILD\l8w8jwt\source"
    if (Test-Path $l8w8jwtSource) {
        cd $l8w8jwtSource
        Remove-Item "CMakeCache.txt" -ErrorAction SilentlyContinue
        Remove-Item -Recurse "CMakeFiles" -ErrorAction SilentlyContinue
        
        & $CMAKE `
            -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
            -DCMAKE_MSVC_RUNTIME_LIBRARY="`$<`$<CONFIG:Debug>:MultiThreadedDebug>`$<`$<CONFIG:Release>:MultiThreaded>" `
            -DBUILD_SHARED_LIBS=OFF `
            -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
            -DL8W8JWT_ENABLE_TESTS=OFF `
            .
        
        & $CMAKE --build . --config Release
        & $CMAKE --build . --config Debug
        
        # l8w8jwt requires manual install/consolidation with mbedtls
        Write-Host "  Consolidating l8w8jwt with mbedtls libraries..." -ForegroundColor Gray
        
        # Ensure install\lib exists
        if (-not (Test-Path "$REPO_ROOT\install\lib")) {
            mkdir "$REPO_ROOT\install\lib" -Force | Out-Null
        }
        
        # Consolidate Release libraries
        if (Test-Path "Release\l8w8jwt.lib") {
            $mbedCryptoRelease = "mbedtls\library\Release\mbedcrypto.lib"
            $mbedTlsRelease = "mbedtls\library\Release\mbedtls.lib"
            $mbedX509Release = "mbedtls\library\Release\mbedx509.lib"
            
            if ((Test-Path $mbedCryptoRelease) -and (Test-Path $mbedTlsRelease) -and (Test-Path $mbedX509Release)) {
                $LINK = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
                & $LINK /LIB /OUT:"$REPO_ROOT\install\lib\libl8w8jwt.lib" /LTCG `
                    "Release\l8w8jwt.lib" `
                    $mbedCryptoRelease `
                    $mbedTlsRelease `
                    $mbedX509Release
                Write-Host "    Consolidated Release: libl8w8jwt.lib" -ForegroundColor Green
            }
        }
        
        # Consolidate Debug libraries
        if (Test-Path "Debug\l8w8jwt.lib") {
            $mbedCryptoDebug = "mbedtls\library\Debug\mbedcrypto.lib"
            $mbedTlsDebug = "mbedtls\library\Debug\mbedtls.lib"
            $mbedX509Debug = "mbedtls\library\Debug\mbedx509.lib"
            
            if ((Test-Path $mbedCryptoDebug) -and (Test-Path $mbedTlsDebug) -and (Test-Path $mbedX509Debug)) {
                $LINK = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
                & $LINK /LIB /OUT:"$REPO_ROOT\install\lib\libl8w8jwtd.lib" /LTCG `
                    "Debug\l8w8jwt.lib" `
                    $mbedCryptoDebug `
                    $mbedTlsDebug `
                    $mbedX509Debug
                Write-Host "    Consolidated Debug: libl8w8jwtd.lib" -ForegroundColor Green
            }
        }
        
        Write-Success "l8w8jwt rebuilt"
        cd $REPO_ROOT
    }
    
    # Rebuild libxml2 with static CRT using CMake
    Write-Host "`nRebuilding libxml2 with static CRT..."
    $libxml2Source = "external\BUILD\libxml2\source"
    if (Test-Path $libxml2Source) {
        $libxml2Build = "external\BUILD\libxml2\cmake_build"
        
        # Clean previous CMake build
        if (Test-Path $libxml2Build) {
            Write-Host "  Cleaning previous libxml2 CMake build..." -ForegroundColor Gray
            Remove-Item -Recurse -Force $libxml2Build -ErrorAction SilentlyContinue
        }
        
        mkdir $libxml2Build -Force | Out-Null
        cd $libxml2Build
        
        & $CMAKE `
            -G "Visual Studio 17 2022" -A x64 `
            -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
            -DCMAKE_MSVC_RUNTIME_LIBRARY="`$<`$<CONFIG:Debug>:MultiThreadedDebug>`$<`$<CONFIG:Release>:MultiThreaded>" `
            -DBUILD_SHARED_LIBS=OFF `
            -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
            -DCMAKE_DEBUG_POSTFIX="d" `
            -DLIBXML2_WITH_PYTHON=OFF `
            -DLIBXML2_WITH_ICONV=OFF `
            -DLIBXML2_WITH_LZMA=OFF `
            -DLIBXML2_WITH_ZLIB=OFF `
            -DLIBXML2_WITH_FTP=OFF `
            -DLIBXML2_WITH_HTTP=OFF `
            -DLIBXML2_WITH_THREADS=ON `
            "..\source"
        
        Write-Host "  Building Release configuration..." -ForegroundColor Gray
        & $CMAKE --build . --config Release --target LibXml2
        
        Write-Host "  Building Debug configuration..." -ForegroundColor Gray
        & $CMAKE --build . --config Debug --target LibXml2
        
        # Copy libraries to install directory
        Write-Host "  Installing libraries..." -ForegroundColor Gray
        if (-not (Test-Path "$REPO_ROOT\install\lib")) {
            mkdir "$REPO_ROOT\install\lib" -Force | Out-Null
        }
        
        # libxml2 CMake creates libxml2s.lib (static release) and libxml2sd.lib (static debug)
        # Copy and rename to match SDK naming convention (libxml2_a.lib)
        if (Test-Path "Release\libxml2s.lib") {
            Copy-Item "Release\libxml2s.lib" "$REPO_ROOT\install\lib\libxml2_a.lib" -Force
            Write-Host "    Installed: libxml2_a.lib (Release)" -ForegroundColor Green
        }
        if (Test-Path "Debug\libxml2sd.lib") {
            Copy-Item "Debug\libxml2sd.lib" "$REPO_ROOT\install\lib\libxml2_ad.lib" -Force
            Write-Host "    Installed: libxml2_ad.lib (Debug)" -ForegroundColor Green
        }
        
        # Also copy headers
        if (Test-Path "..\source\include\libxml") {
            $includeDir = "$REPO_ROOT\install\include\libxml2"
            if (-not (Test-Path $includeDir)) {
                mkdir $includeDir -Force |Out-Null
            }
            Copy-Item "..\source\include\libxml" "$includeDir\" -Recurse -Force
        }
        
        Write-Success "libxml2 rebuilt with static CRT"
        cd $REPO_ROOT
    }
}

# ============================================================================
# Step 4: Verify Static CRT in External Libs
# ============================================================================

Write-Step "Step 4: Verifying Static CRT in External Libraries"

cd $REPO_ROOT

$externalLibs = @(
    @{Path="install\lib\zlib.lib"; Name="zlib.lib"},
    @{Path="install\lib\zlibd.lib"; Name="zlibd.lib"},
    @{Path="install\lib\lz4.lib"; Name="lz4.lib"},
    @{Path="install\lib\lz4d.lib"; Name="lz4d.lib"},
    @{Path="install\lib\cjson.lib"; Name="cjson.lib"},
    @{Path="install\lib\cjsond.lib"; Name="cjsond.lib"},
    @{Path="install\lib\ccronexpr.lib"; Name="ccronexpr.lib"},
    @{Path="install\lib\ccronexprd.lib"; Name="ccronexprd.lib"},
    @{Path="install\lib\libl8w8jwt.lib"; Name="libl8w8jwt.lib"},
    @{Path="install\lib\libl8w8jwtd.lib"; Name="libl8w8jwtd.lib"},
    @{Path="install\lib\libxml2_a.lib"; Name="libxml2_a.lib"},
    @{Path="install\lib\libxml2_ad.lib"; Name="libxml2_ad.lib"}
)

$allExternalsOk = $true
foreach ($lib in $externalLibs) {
    $result = Test-CRT -LibPath $lib.Path -LibName $lib.Name
    if (-not $result) {
        $allExternalsOk = $false
    }
}

if ($allExternalsOk) {
    Write-Success "All external libraries verified with static CRT"
} else {
    Write-Error-Custom "Some external libraries have incorrect CRT. Review output above."
    if (-not $VerifyOnly) {
        Write-Host "`nConsider re-running with -SkipClean to rebuild externals only." -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================================
# Step 5: Build SDK Solution
# ============================================================================

if (-not $VerifyOnly) {
    Write-Step "Step 5: Building SDK Solution (Debug and Release)"
    
    cd $REPO_ROOT
    
    Write-Host "Cleaning SDK solution (Debug and Release)..."
    & $MSBUILD "rtsdk.sln" /t:Clean /p:Configuration=Debug_Mdd /p:Platform=x64
    & $MSBUILD "rtsdk.sln" /t:Clean /p:Configuration=Release_MD /p:Platform=x64
    
    Write-Host "`nBuilding librssl.lib (static library - Debug)..."
    & $MSBUILD "Cpp-C\Eta\Impl\Codec\librssl.vcxproj" /p:Configuration=Debug_Mdd /p:Platform=x64
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "librssl.lib (Debug) build failed"
        exit 1
    }
    
    Write-Host "`nBuilding librssl.lib (static library - Release)..."
    & $MSBUILD "Cpp-C\Eta\Impl\Codec\librssl.vcxproj" /p:Configuration=Release_MD /p:Platform=x64
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "librssl.lib (Release) build failed"
        exit 1
    }
    
    Write-Success "librssl.lib built successfully (Debug and Release)"
}

# ============================================================================
# Step 6: Verify SDK Static Libraries
# ============================================================================

Write-Step "Step 6: Verifying SDK Static Libraries (Debug and Release)"

cd $REPO_ROOT

$sdkLibs = @(
    @{Path="Cpp-C\Eta\Libs\WIN_64_VS143\Debug_Mdd\librssl.lib"; Name="librssl.lib (Debug)"},
    @{Path="Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\librssl.lib"; Name="librssl.lib (Release)"}
)

$allSdkLibsOk = $true
foreach ($lib in $sdkLibs) {
    $result = Test-CRT -LibPath $lib.Path -LibName $lib.Name
    if (-not $result) {
        $allSdkLibsOk = $false
    }
}

if ($allSdkLibsOk) {
    Write-Success "All SDK static libraries verified with static CRT"
} else {
    Write-Error-Custom "SDK libraries have mixed CRT. Attempting rebuild..."
    
    if (-not $VerifyOnly) {
        # Full clean and rebuild both configurations
        & $MSBUILD "rtsdk.sln" /t:Clean /p:Configuration=Debug_Mdd /p:Platform=x64
        & $MSBUILD "rtsdk.sln" /t:Clean /p:Configuration=Release_MD /p:Platform=x64
        & $MSBUILD "Cpp-C\Eta\Impl\Codec\librssl.vcxproj" /p:Configuration=Debug_Mdd /p:Platform=x64
        & $MSBUILD "Cpp-C\Eta\Impl\Codec\librssl.vcxproj" /p:Configuration=Release_MD /p:Platform=x64
        
        # Verify again
        $resultDebug = Test-CRT -LibPath "Cpp-C\Eta\Libs\WIN_64_VS143\Debug_Mdd\librssl.lib" -LibName "librssl.lib (Debug after rebuild)"
        $resultRelease = Test-CRT -LibPath "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\librssl.lib" -LibName "librssl.lib (Release after rebuild)"
        if (-not ($resultDebug -and $resultRelease)) {
            Write-Error-Custom "librssl.lib still has mixed CRT after rebuild"
            exit 1
        }
    } else {
        exit 1
    }
}

# ============================================================================
# Step 7: Build Shared Libraries
# ============================================================================

if (-not $VerifyOnly) {
    Write-Step "Step 7: Building Shared Libraries (Debug and Release)"
    
    cd $REPO_ROOT
    
    Write-Host "Building librssl.dll (Debug)..."
    & $MSBUILD "Cpp-C\Eta\Impl\Codec\librssl_shared.vcxproj" /p:Configuration=Debug_Mdd /p:Platform=x64
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "librssl.dll (Debug) build failed"
        exit 1
    }
    
    Write-Host "`nBuilding librssl.dll (Release)..."
    & $MSBUILD "Cpp-C\Eta\Impl\Codec\librssl_shared.vcxproj" /p:Configuration=Release_MD /p:Platform=x64
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "librssl.dll (Release) build failed"
        exit 1
    }
    
    Write-Host "`nBuilding full SDK solution (Debug)..."
    & $MSBUILD "rtsdk.sln" /p:Configuration=Debug_Mdd /p:Platform=x64 /m
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "SDK solution (Debug) build failed"
        exit 1
    }
    
    Write-Host "`nBuilding full SDK solution (Release)..."
    & $MSBUILD "rtsdk.sln" /p:Configuration=Release_MD /p:Platform=x64 /m
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "SDK solution (Release) build failed"
        exit 1
    }
    
    Write-Success "SDK solution built successfully (Debug and Release)"
}

# ============================================================================
# Step 8: Verify Output Artifacts
# ============================================================================

Write-Step "Step 8: Verifying Output Artifacts (Debug and Release)"

cd $REPO_ROOT

$artifactsDebug = @(
    "Cpp-C\Eta\Libs\WIN_64_VS143\Debug_Mdd\librssl.lib",
    "Cpp-C\Eta\Libs\WIN_64_VS143\Debug_Mdd\Shared\librssl.dll",
    "Cpp-C\Eta\Libs\WIN_64_VS143\Debug_Mdd\Shared\librsslVA.dll",
    "Cpp-C\Ema\Libs\WIN_64_VS143\Debug_Mdd\Shared\libema.dll"
)

$artifactsRelease = @(
    "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\librssl.lib",
    "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\Shared\librssl.dll",
    "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\Shared\librsslVA.dll",
    "Cpp-C\Ema\Libs\WIN_64_VS143\Release_MD\Shared\libema.dll"
)

Write-Host "`nChecking DEBUG artifacts..."
$allDebugPresent = $true
foreach ($artifact in $artifactsDebug) {
    if (Test-Path $artifact) {
        Write-Host "  [OK] $artifact" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] $artifact (NOT FOUND)" -ForegroundColor Red
        $allDebugPresent = $false
    }
}

Write-Host "`nChecking RELEASE artifacts..."
$allReleasePresent = $true
foreach ($artifact in $artifactsRelease) {
    if (Test-Path $artifact) {
        Write-Host "  [OK] $artifact" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] $artifact (NOT FOUND)" -ForegroundColor Red
        $allReleasePresent = $false
    }
}

$allArtifactsPresent = $allDebugPresent -and $allReleasePresent

# ============================================================================
# Summary
# ============================================================================

Write-Step "Build Summary"

if ($VerifyOnly) {
    Write-Host "Verification complete. Review results above." -ForegroundColor Cyan
} elseif ($allArtifactsPresent -and $allExternalsOk -and $allSdkLibsOk) {
    Write-Success "BUILD SUCCESSFUL!"
    Write-Host "`nAll artifacts built with static CRT:" -ForegroundColor Green
    Write-Host "  - Debug builds use /MTd (LIBCMTD)" -ForegroundColor Green
    Write-Host "  - Release builds use /MT (LIBCMT)" -ForegroundColor Green
    Write-Host "  - External libraries: [OK]" -ForegroundColor Green
    Write-Host "  - SDK static libraries: [OK]" -ForegroundColor Green
    Write-Host "  - SDK shared libraries: [OK]" -ForegroundColor Green
} else {
    Write-Error-Custom "BUILD INCOMPLETE OR FAILED"
    Write-Host "Review the output above for details." -ForegroundColor Yellow
    exit 1
}
