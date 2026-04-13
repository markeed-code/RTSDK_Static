# Real-Time SDK: Static CRT Build Guide (Debug_Mdd & Release_MD x64)

## Overview

This guide documents the process to build the Real-Time SDK (x64, Debug_Mdd and Release_MD) with all externals statically linked against the MSVC runtime library. This eliminates CRT version conflicts and simplifies deployment.

- **Debug builds** use `/MTd` (MultiThreadedDebug → LIBCMTD)
- **Release builds** use `/MT` (MultiThreaded → LIBCMT)

### Problem Statement

Prior builds encountered unresolved linker errors due to mismatched CRT versions between externals and the SDK:
- Externals compiled with `/MD` or `/MDd` (dynamic CRT)
- SDK targets `/MT` or `/MTd` (static CRT)
- Result: unresolved symbol errors during linking of shared libraries (`librsslVA_shared`, `libema_shared`)

Additionally, `l8w8jwt` depends on mbedtls libraries, which must be properly linked into the consolidated external lib to avoid missing mbedtls symbols during final linking.

### Build Goals

✓ All externals use static CRT (`/DEFAULTLIB:LIBCMT` for Release, `/DEFAULTLIB:LIBCMTD` for Debug)  
✓ All mbedtls symbols bundled into `libl8w8jwt.lib` and `libl8w8jwtd.lib`  
✓ Clean Debug_Mdd and Release_MD x64 link of EMA and Eta shared libraries  
✓ Zero errors in final MSBuild step for both configurations  

---

## Prerequisites

- **Visual Studio 2022** (Community or higher) with C++ tools
- **CMake** (3.20+, typically bundled in VS2022)
- **Git** (for external repo cloning)
- **Python 3** (required by some external builds)

Verify CMake and tools are available:
```powershell
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --version
```

---

## Automated Build Script (Recommended)

For a fully automated rebuild with static CRT, use the provided PowerShell script:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK
.\rebuild_static_crt.ps1
```

**What the script does:**
- ✓ Cleans all previous artifacts (build, external\BUILD, install)
- ✓ Generates VS2022 solution with static CRT enforced via CMake
- ✓ Rebuilds all external dependencies with correct static CRT:
  - zlib, lz4, libxml2 (both Debug and Release)
  - cjson, ccronexpr (with test builds disabled)
  - l8w8jwt (consolidated with mbedtls libraries)
- ✓ Includes **diagnostic monitoring** for cjson build:
  - Color-coded output showing Debug/Release folder contents
  - Timestamps for each file creation
  - Red error alerts when wrong files appear in wrong folders
  - Helps identify exactly which build stage causes issues
- ✓ Verifies CRT in all libraries using dumpbin
- ✓ Builds SDK solution (Release_MD and Debug_Mdd)
- ✓ Includes retry logic for antivirus file lock issues

**Script Parameters:**
```powershell
# Skip the clean step (use existing build directory)
.\rebuild_static_crt.ps1 -SkipClean

# Skip external rebuilds (only build SDK)
.\rebuild_static_crt.ps1 -SkipExternals

# Only verify CRT in existing libraries (no building)
.\rebuild_static_crt.ps1 -VerifyOnly
```

**Diagnostic Output Example:**

During cjson rebuild, the script shows:
```
[STAGE 2: Building Release configuration]
  [DEBUG MONITOR - After Release build]
    <no .lib files>
  [RELEASE MONITOR - After Release build]
    cjson.lib (63700 bytes) - 22:40:11
  ✅ OK at After Release build: Files in correct locations

[STAGE 3: Building Debug configuration]
  [DEBUG MONITOR - After Debug build]
    cjsond.lib (63698 bytes) - 22:40:19
  [RELEASE MONITOR - After Debug build]
    cjson.lib (63700 bytes) - 22:40:11
  ✅ OK at After Debug build: Files in correct locations
```

If problems occur, you'll see:
```
  ❌ ERROR at After Debug build: Debug/cjson.lib exists (should be cjsond.lib)
```

This immediately identifies which build step is creating wrong files, making troubleshooting much easier.

**For manual step-by-step process**, continue to the sections below.

---

## Step-by-Step Build Process

### 1. Clean Previous Artifacts (Recommended for Clean Rebuild)

Remove all build artifacts to force a clean rebuild with static CRT:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK

# Clean all build directories
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force external\BUILD -ErrorAction SilentlyContinue

# Clean install directory to force rebuild of ALL externals with static CRT
# This is CRITICAL - existing install/lib files may have dynamic CRT (MSVCRT)
Remove-Item -Recurse -Force install -ErrorAction SilentlyContinue

Write-Host "All artifacts cleaned - externals will rebuild with static CRT"
```

**Important:** CMake's ExternalProject system will automatically rebuild all externals (zlib, lz4, libxml2, curl, cjson, ccronexpr, l8w8jwt) during the CMake configuration step. This takes several minutes but ensures all libraries use static CRT (`/DEFAULTLIB:LIBCMT`).

### 2. Generate VS2022 Solution (CMake Configuration)

Create or update the build directory and generate the Visual Studio solution:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK
if (-not (Test-Path build)) { mkdir build }
cd build

& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
  -DCMAKE_MSVC_RUNTIME_LIBRARY="$<$<CONFIG:Debug_Mdd>:MultiThreadedDebug>$<$<CONFIG:Debug>:MultiThreadedDebug>$<$<CONFIG:Release_MD>:MultiThreaded>$<$<CONFIG:Release>:MultiThreaded>" `
  -Dlibxml2_USE_INSTALLED:BOOL=OFF `
  -DBUILD_RTSDK-BINARYPACK:BOOL=OFF `
  -DRTSDK_OPT_BUILD_ETA_EMA_LIBRARIES:BOOL=ON `
  -DBUILD_UNIT_TESTS:BOOL=OFF `
  -DBUILD_ETA_EXAMPLES:BOOL=OFF `
  -DBUILD_EMA_EXAMPLES:BOOL=OFF `
  -DBUILD_EMA_DOXYGEN:BOOL=OFF `
  -DBUILD_ETA_TRAINING:BOOL=OFF `
  -DBUILD_ETA_PERFTOOLS:BOOL=OFF `
  ..
```

**What this does:**
- Generates `build/rtsdk.sln` for Visual Studio 2022 (x64 platform)
- Disables non-essential targets (examples, tests, doxygen) for faster iteration
- Triggers automatic configuration of external projects (l8w8jwt, ccronexpr, cjson, zlib, lz4, libxml2, etc.)
- CMake applies generator expression for static CRT:
  - Debug/Debug_Mdd → MultiThreadedDebug (/MTd → LIBCMTD)
  - Release/Release_MD → MultiThreaded (/MT → LIBCMT)

### 3. Rebuild Key Externals with Static CRT

The CMake configuration automatically configures externals with static CRT options. However, if needed, you can selectively rebuild an external:

**Example: Rebuild ccronexpr (Debug & Release)**
```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\ccronexpr\build --config Debug
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\ccronexpr\build --config Release
```

**Example: Rebuild cjson (Debug & Release)**

**Important:** cjson requires special configuration to ensure correct CRT and DEBUG_POSTFIX behavior. See the troubleshooting section "cjson libraries have wrong CRT or wrong files in Debug/Release folders" for details.

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\cjson\source
Remove-Item "CMakeCache.txt" -ErrorAction SilentlyContinue
Remove-Item -Recurse "CMakeFiles" -ErrorAction SilentlyContinue

& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_POLICY_DEFAULT_CMP0091=OLD `
  -DCMAKE_C_FLAGS_DEBUG="/MTd /Zi /Ob0 /Od /RTC1" `
  -DCMAKE_C_FLAGS_RELEASE="/MT /O2 /Ob2 /DNDEBUG" `
  -DCMAKE_DEBUG_POSTFIX=d `
  -DENABLE_CJSON_TEST:BOOL=OFF `
  -DENABLE_CUSTOM_COMPILER_FLAGS:BOOL=OFF `
  -DBUILD_SHARED_LIBS=OFF `
  -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
  .

# Build only the cjson target (not tests)
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config Debug --target cjson
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config Release --target cjson

# Verify only correct files exist
Get-ChildItem "Debug\*.lib"    # Should show only: cjsond.lib
Get-ChildItem "Release\*.lib"  # Should show only: cjson.lib

# Copy to install
if (-not (Test-Path "$REPO_ROOT\install\lib")) { mkdir "$REPO_ROOT\install\lib" -Force | Out-Null }
Copy-Item "Debug\cjsond.lib" "$REPO_ROOT\install\lib\cjsond.lib" -Force
Copy-Item "Release\cjson.lib" "$REPO_ROOT\install\lib\cjson.lib" -Force
```

**Example: Rebuild l8w8jwt (Debug & Release)**
```powershell
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\l8w8jwt\build --config Debug
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\l8w8jwt\build --config Release
```

**Example: Rebuild zlib (Debug & Release)**

If zlib was built with dynamic CRT, reconfigure and rebuild:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\zlib\source
Remove-Item CMakeCache.txt -ErrorAction SilentlyContinue
Remove-Item -Recurse CMakeFiles -ErrorAction SilentlyContinue

& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded `
  -DBUILD_SHARED_LIBS=OFF `
  -DCMAKE_INSTALL_PREFIX="c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install" `
  .

& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config Release
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config Debug

# Copy to install
Copy-Item "Release\zlib.lib" "..\..\..\..\install\lib\zlib.lib" -Force
Copy-Item "Debug\zlibd.lib" "..\..\..\..\install\lib\zlibd.lib" -Force
```

**Example: Rebuild lz4 (Debug & Release)**

If lz4 was built with dynamic CRT, reconfigure and rebuild:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\lz4\source\build\cmake
Remove-Item CMakeCache.txt -ErrorAction SilentlyContinue
Remove-Item -Recurse CMakeFiles -ErrorAction SilentlyContinue

& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded `
  -DBUILD_SHARED_LIBS=OFF `
  -DCMAKE_INSTALL_PREFIX="c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install" `
  -DLZ4_BUILD_CLI=OFF `
  .

& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config Release
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config Debug

# Copy to install
Copy-Item "Release\lz4.lib" "..\..\..\..\..\install\lib\lz4.lib" -Force
Copy-Item "Debug\lz4.lib" "..\..\..\..\..\install\lib\lz4d.lib" -Force
```

### 4. Verify Static CRT in Rebuilt Libs

Use Visual Studio's `dumpbin` tool to confirm `/DEFAULTLIB:LIBCMT` (static CRT) in each rebuilt external:

```powershell
$DUMPBIN = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"

# Check ccronexpr
& $DUMPBIN /directives install\lib\ccronexpr.lib | Select-String "DEFAULTLIB"

# Check cjson
& $DUMPBIN /directives install\lib\cjson.lib | Select-String "DEFAULTLIB"

# Check l8w8jwt
& $DUMPBIN /directives install\lib\libl8w8jwt.lib | Select-String "DEFAULTLIB"

# Check zlib
& $DUMPBIN /directives install\lib\zlib.lib | Select-String "DEFAULTLIB"

# Check lz4
& $DUMPBIN /directives install\lib\lz4.lib | Select-String "DEFAULTLIB"
```

**Expected output for each:** `/DEFAULTLIB:LIBCMT` (NOT `MSVCRTD` or `MSVCRT`)

### 5. Verify and Rebuild SDK Static Libraries (if needed)

After changing CRT settings, SDK static libraries may contain mixed CRT references from previous incremental builds. Verify key SDK libraries before building shared DLLs:

```powershell
$DUMPBIN = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"

# Check librssl.lib (Eta core library)
& $DUMPBIN /directives "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\librssl.lib" | Select-String "DEFAULTLIB:(LIBCMT|MSVCRT)" | Group-Object | Select-Object Count, Name
```

**Expected output:** Single entry showing `/DEFAULTLIB:LIBCMT` for all objects.

**If mixed CRT detected** (both LIBCMT and MSVCRT entries):

1. Clean and rebuild the affected SDK library:
```powershell
$MSBUILD = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"

# Clean librssl
& $MSBUILD rtsdk.sln /t:Clean /p:Configuration=Release_MD /p:Platform=x64

# Rebuild librssl.lib only (static lib)
& $MSBUILD Cpp-C\Eta\Impl\Codec\librssl.vcxproj /p:Configuration=Release_MD /p:Platform=x64
```

2. Verify the rebuilt library:
```powershell
& $DUMPBIN /directives "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\librssl.lib" | Select-String "DEFAULTLIB:(LIBCMT|MSVCRT)" | Group-Object | Select-Object Count, Name
```

**Note:** This issue occurs when CMake configuration is updated to use static CRT but object files from a previous dynamic CRT build are cached. A full clean forces recompilation of all sources with the correct `/MT` flag.

#### Special Case: libxml2 Debug Library and Mixed CRT in libema.lib

**Problem:** Debug builds of `libema.lib` may exhibit mixed CRT linkage (both `/DEFAULTLIB:LIBCMT` and `/DEFAULTLIB:LIBCMTD`), even when all external libraries are correctly built with static CRT.

**Root Cause:** The libxml2 external library requires separate debug and release builds:
- **Release**: `libxml2_a.lib` (built with `/MT` → LIBCMT) ✓
- **Debug**: `libxml2_ad.lib` (built with `/MTd` → LIBCMTD) ✓

If `libxml2_ad.lib` is missing, the CMake `LibXml2::LibXml2` target defaults to using `libxml2_a.lib` for both configurations. This causes debug SDK builds to link the release libxml2 library, introducing `/DEFAULTLIB:LIBCMT` into debug libraries that should only have `/DEFAULTLIB:LIBCMTD`.

**Diagnosis:**
```powershell
$DUMPBIN = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"

# Check if debug libema.lib has mixed CRT
& $DUMPBIN /directives "Cpp-C\Ema\Libs\WIN_64_VS143\Debug_MDd\libema.lib" | Select-String "DEFAULTLIB" | Select-String "LIBCMT" | Sort-Object -Unique
```

**Expected (correct):** Only `/DEFAULTLIB:LIBCMTD`  
**Problem:** Both `/DEFAULTLIB:LIBCMT` and `/DEFAULTLIB:LIBCMTD`

**Solution:**

1. **Verify libxml2 debug library exists:**
   ```powershell
   if (Test-Path "build\install\lib\libxml2_ad.lib") {
       Write-Host "✅ Debug library exists" -ForegroundColor Green
   } else {
       Write-Host "❌ Missing libxml2_ad.lib - will cause mixed CRT!" -ForegroundColor Red
   }
   ```

2. **Build libxml2 debug library** (if missing):
   ```powershell
   cd build\external\BUILD\libxml2\source
   
   $CMAKE = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
   
   # Configure with Debug static CRT
   & $CMAKE -G "Visual Studio 17 2022" -A x64 `
     -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
     -DCMAKE_MSVC_RUNTIME_LIBRARY="MultiThreadedDebug" `
     -DBUILD_SHARED_LIBS=OFF `
     -DLIBXML2_WITH_ICONV=OFF `
     -DLIBXML2_WITH_ZLIB=OFF `
     -DLIBXML2_WITH_PYTHON=OFF `
     -DLIBXML2_WITH_LZMA=OFF `
     -S . -B build_debug
   
   # Build debug configuration
   & $CMAKE --build build_debug --config Debug --target LibXml2
   
   # Copy debug library to install directory
   Copy-Item "build_debug\Debug\libxml2sd.lib" "../../../../install/lib/libxml2_ad.lib" -Force
   ```

3. **Verify both libxml2 libraries have correct CRT:**
   ```powershell
   $DUMPBIN = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
   
   Write-Host "`nlibxml2_a.lib (Release):" -ForegroundColor Yellow
   & $DUMPBIN /directives "build\install\lib\libxml2_a.lib" | Select-String "DEFAULTLIB" | Sort-Object -Unique
   # Expected: /DEFAULTLIB:LIBCMT
   
   Write-Host "`nlibxml2_ad.lib (Debug):" -ForegroundColor Yellow
   & $DUMPBIN /directives "build\install\lib\libxml2_ad.lib" | Select-String "DEFAULTLIB" | Sort-Object -Unique
   # Expected: /DEFAULTLIB:LIBCMTD
   ```

4. **Rebuild libema.lib:**
   ```powershell
   $MSBUILD = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
   
   # Rebuild Debug_MDd configuration
   & $MSBUILD "build\Cpp-C\Ema\Src\Access\libema.vcxproj" `
     /p:Configuration=Debug_MDd /p:Platform=x64 /t:Rebuild
   ```

5. **Verify fix:**
   ```powershell
   & $DUMPBIN /directives "Cpp-C\Ema\Libs\WIN_64_VS143\Debug_MDd\libema.lib" | Select-String "DEFAULTLIB" | Select-String "LIBCMT" | Sort-Object -Unique
   # Expected: Only /DEFAULTLIB:LIBCMTD (no LIBCMT)
   ```

**Technical Details:**

The fix is implemented in `CMake/addExternal_libxml2.cmake` (lines 380-384), which sets configuration-specific `IMPORTED_LOCATION` properties on the `LibXml2::LibXml2` target:

```cmake
# Set configuration-specific library locations for static CRT support
if (WIN32)
    # Debug configuration uses libxml2_ad.lib
    set_property(TARGET LibXml2::LibXml2 PROPERTY IMPORTED_LOCATION_DEBUG_MDD "${libxml2_install}/lib/libxml2_ad.lib")
    set_property(TARGET LibXml2::LibXml2 PROPERTY IMPORTED_LOCATION_DEBUG "${libxml2_install}/lib/libxml2_ad.lib")
    # Release configuration uses libxml2_a.lib
    set_property(TARGET LibXml2::LibXml2 PROPERTY IMPORTED_LOCATION_RELEASE_MD "${libxml2_install}/lib/libxml2_a.lib")
    set_property(TARGET LibXml2::LibXml2 PROPERTY IMPORTED_LOCATION_RELEASE "${libxml2_install}/lib/libxml2_a.lib")
endif()
```

This ensures CMake uses the correct library variant for each build configuration, preventing CRT mismatches.

**Note:** The `rebuild_static_crt.ps1` script (Step 3, lines 426-490) automatically builds both debug and release libxml2 libraries using CMake, eliminating this issue when using the automated rebuild process.

### 6. Consolidate l8w8jwt with mbedtls Libraries

The `l8w8jwt` external depends on mbedtls. The SDK's external script automatically consolidates them, but if manual repackaging is needed:

```powershell
$LINK = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"

# Merge Release libs
& $LINK /LIB /OUT:"c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install\lib\libl8w8jwt.lib" /LTCG `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\Release\l8w8jwt.lib" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\mbedtls\library\Release\mbedcrypto.lib" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\mbedtls\library\Release\mbedtls.lib" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\mbedtls\library\Release\mbedx509.lib"

# Merge Debug libs
& $LINK /LIB /OUT:"c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\install\lib\libl8w8jwtd.lib" /LTCG `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\Debug\l8w8jwt.lib" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\mbedtls\library\Debug\mbedcrypto.lib" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\mbedtls\library\Debug\mbedtls.lib" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD\l8w8jwt\build\mbedtls\library\Debug\mbedx509.lib"
```

**What this does:**
- Uses Link Tool's Library Manager (`/LIB`) to merge multiple static libraries into one
- `/LTCG` enables Link Time Code Generation for optimization
- Ensures all mbedtls symbols (mbedcrypto, mbedtls, mbedx509) are accessible during SDK linking

### 7. Build the SDK Solution (Release_MD x64)

Invoke MSBuild to compile and link the SDK with all externals:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK

& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  "c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK\rtsdk.sln" `
  /p:Configuration=Release_MD /p:Platform=x64 /m
```

**Parameters:**
- `/p:Configuration=Release_MD` – Use Release_MD configuration
- `/p:Platform=x64` – Target 64-bit platform
- `/m` – Enable parallel compilation for faster builds

**Expected output (tail):**
```
Build succeeded.
    0 Warning(s)
    0 Error(s)
```

**If DLL linking fails with LNK1257 (code generation failed):** This typically indicates mixed CRT in SDK static libraries. Return to Step 5 to verify and rebuild SDK libraries.

### 8. Verify Output Artifacts

Check that shared libraries were successfully built:

```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK

# Eta Reactor library
Test-Path "Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\Shared\librsslVA.dll"

# EMA Access library
Test-Path "Cpp-C\Ema\Libs\WIN_64_VS143\Release_MD\Shared\libema.dll"

# List all Release_MD artifacts
Get-ChildItem -Path "Cpp-C\*\Libs\*\Release_MD\Shared\*.dll" -Recurse
```

---

## Key Configuration Details

### CRT Control via CMake

Static CRT is enforced through:

1. **CMake policy `CMP0091=NEW`** in external projects:
   - Tells CMake to use `CMAKE_MSVC_RUNTIME_LIBRARY` variable instead of legacy `/MD` or `/MT` flags

2. **`CMAKE_MSVC_RUNTIME_LIBRARY` with generator expression** in `CMake/rcdevCompilerOptions.cmake`:
   ```cmake
   set(CMAKE_MSVC_RUNTIME_LIBRARY 
       "$<$<CONFIG:Debug_Mdd>:MultiThreadedDebug>$<$<CONFIG:Debug>:MultiThreadedDebug>$<$<CONFIG:Release_MD>:MultiThreaded>$<$<CONFIG:Release>:MultiThreaded>" 
       CACHE STRING "" FORCE)
   ```
   - Debug configurations → MultiThreadedDebug (/MTd → LIBCMTD)
   - Release configurations → MultiThreaded (/MT → LIBCMT)
   - Passed to all externals via `CMAKE_MSVC_RUNTIME_LIBRARY_FOR_EXTERNAL`

3. **Verification via `dumpbin /directives`**:
   - Debug libs show `/DEFAULTLIB:LIBCMTD` for static CRT Debug
   - Release libs show `/DEFAULTLIB:LIBCMT` for static CRT Release
   - Shows `/DEFAULTLIB:MSVCRTD` or `/DEFAULTLIB:MSVCRT` if CRT mismatch remains

### l8w8jwt + mbedtls Consolidation

The external build script (`CMake/addExternal_l8w8jwt.cmake`):
- On Windows: uses the Library Manager to merge l8w8jwt.lib + mbedcrypto/mbedtls/mbedx509 into a single `libl8w8jwt.lib`
- On Linux: extracts object files and re-archives them
- This ensures the SDK linker resolves all mbedtls symbols from a single lib without missing dependency errors

---

## Troubleshooting

### External libraries built with dynamic CRT (MSVCRT/MSVCRTD) instead of static CRT (LIBCMT/LIBCMTD)

**Cause:** CMake not enforcing static CRT on external projects.  
**Solution:**
1. Ensure the CMake command includes these critical flags:
   - `-DCMAKE_POLICY_DEFAULT_CMP0091=NEW`
   - `-DCMAKE_MSVC_RUNTIME_LIBRARY` with generator expression for both Debug and Release
2. These flags MUST be passed at the top-level CMake configuration (Step 2)
3. Clean all artifacts (Step 1) and re-run CMake configuration
4. Verify rebuilt libs with `dumpbin /directives install\lib\*.lib | Select-String "DEFAULTLIB"`
   - Debug libs should show LIBCMTD
   - Release libs should show LIBCMT

### "Unresolved external symbol mbedtls_*"

**Cause:** l8w8jwt.lib does not include mbedtls symbols.  
**Solution:** Re-run step 5 (consolidate l8w8jwt with mbedtls libs).

### Linker error about MSVor SDK libraries compiled with `/MD` instead of `/MT`.  
**Solution:**
1. Run `dumpbin /directives` on external libs (`install\lib\*.lib`) to identify mismatched externals
2. Run `dumpbin /directives` on SDK libs (`Cpp-C\Eta\Libs\WIN_64_VS143\Release_MD\librssl.lib`) to check for mixed CRT
3. Rebuild the offending library with `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded` or perform a full clean+rebuild
4. Re-run MSBuild on the SDK

### LNK1257: code generation failed during DLL linking

**Cause:** Mixed CRT objects within SDK static libraries (e.g., librssl.lib) from incremental builds.  
**Solution:**
1. Verify SDK static libraries with `dumpbin /directives` (see Step 5)
2. Clean and rebuild the specific SDK project: `MSBuild <project>.vcxproj /p:Configuration=Release_MD /p:Platform=x64`
3. For stubborn cases, perform a full solution clean: `MSBuild rtsdk.sln /t:Clean` on each external lib to identify the offender
2. Rebuild that external with `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`
3. Re-run MSBuild on the SDK

### CMake generation fails

**Cause:** Missing tools (Python 3, Git, or proper CMake version).  
**Solution:**
- Verify Python 3 is in PATH: `python --version`
- Verify Git is available: `git --version`
- Use VS2022's bundled CMake path as shown in step 2

### "Access is denied" error during external package extraction

**Symptom:**
```
-- extracting... [rename]
file RENAME failed to rename because: Access is denied
```

**Cause:** Windows Defender or antivirus software is scanning the extracted files, locking them during the CMake `file(RENAME)` operation.

**Solutions:**

1. **Add Windows Defender Exclusions** (Recommended):
   - Open Windows Security → Virus & threat protection → Exclusions
   - Add folder exclusions for:
     - `C:\Users\<YourUser>\Reuters\RTSDK_GIT\Real-Time-SDK\external\BUILD`
     - `C:\Users\<YourUser>\Reuters\RTSDK_GIT\Real-Time-SDK\install`

2. **Temporarily Disable Real-time Scanning** (during build only):
   - Windows Security → Virus & threat protection → Manage settings
   - Turn off "Real-time protection" temporarily
   - Re-enable after build completes

3. **Use Retry Logic**:
   - The `rebuild_static_crt.ps1` script includes automatic retry logic with delays
   - It will attempt cleanup 3 times with 2-second delays between attempts

4. **Manual Cleanup** (if automated retry fails):
   ```powershell
   # Wait a few seconds and try again
   Start-Sleep -Seconds 5
   Remove-Item -Recurse -Force "external\BUILD"
   Remove-Item -Recurse -Force "install"
   ```

5. **Run as Administrator**:
   - Right-click PowerShell → "Run as Administrator"
   - May help with permission-related issues

**Note:** This issue is most common on corporate machines with aggressive antivirus policies. Adding folder exclusions is the most reliable long-term solution.

### External libraries built in `build\internal` instead of `external\BUILD`

**Symptom:** After running CMake, external libraries are located in `build\internal\` instead of the expected `external\BUILD\` directory.

**Cause:** Cached CMake variable `RCDEV_EXTERNAL_BINARY_PREFIX` from a previous build with different configuration.

**Solutions:**

1. **Clean CMake Cache** (Recommended):
   ```powershell
   Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
   Remove-Item -Recurse -Force external\BUILD -ErrorAction SilentlyContinue
   Remove-Item CMakeCache.txt -ErrorAction SilentlyContinue
   ```
   Then re-run CMake configuration (Step 2)

2. **Explicitly Set External Directory**:
   Add these flags to your CMake command:
   ```powershell
   -DRCDEV_EXTERNAL_BINARY_PREFIX:PATH="C:\Users\<YourUser>\Reuters\RTSDK_GIT\Real-Time-SDK"
   -DRCDEV_EXTERNAL_INSTALL_PREFIX:PATH="C:\Users\<YourUser>\Reuters\RTSDK_GIT\Real-Time-SDK\install"
   ```
   This forces CMake to use `external\BUILD\` and `install\` directories.

3. **Use the Automated Script**:
   The `rebuild_static_crt.ps1` script automatically sets these paths correctly:
   ```powershell
   .\rebuild_static_crt.ps1
   ```

**Note:** The `build\internal` path typically indicates you're building from a different SDK branch or an older configuration. Always perform a clean build when switching between configurations.

### MSBuild fails mid-solution

**Cause:** Incomplete external builds or cache issues.  
**Solution:**
1. Clean the build directory: `Remove-Item -Recurse -Force build`
2. Re-run CMake configuration (step 2)
3. Re-run MSBuild (step 6)

### cjson libraries have wrong CRT or wrong files in Debug/Release folders

**Symptom:** 
- `install\lib\cjson.lib` has `/DEFAULTLIB:LIBCMTD` instead of `/DEFAULTLIB:LIBCMT`
- Debug folder contains both `cjson.lib` and `cjsond.lib` (should only have `cjsond.lib`)
- Release folder contains `cjsond.lib` (should only have `cjson.lib`)
- File sizes don't match expected values

**Root Causes:**

1. **Test builds creating non-postfixed libraries:**
   - When `ENABLE_CJSON_TEST:BOOL` is not explicitly disabled, cjson builds test targets
   - Test builds create `cjson.lib` without the debug postfix, even in Debug configuration
   - This overwrites or conflicts with the correctly-postfixed `cjsond.lib`

2. **CMP0091 policy and CMAKE_DEBUG_POSTFIX interaction:**
   - When using `CMAKE_POLICY_DEFAULT_CMP0091=NEW`, the `CMAKE_DEBUG_POSTFIX` may not work correctly in all scenarios
   - For cjson specifically, using `CMP0091=OLD` with direct C_FLAGS provides more reliable results

3. **Install target copying wrong files:**
   - Default `cmake --install` may copy libraries in the wrong order or from the wrong configuration
   - Manual file copying with explicit paths ensures correct files are installed

**Solutions:**

1. **In `CMake/addExternal_cjson.cmake`** (already implemented):
   ```cmake
   # Use OLD policy with direct C_FLAGS for reliable CRT control
   list(APPEND _config_options "-DCMAKE_DEBUG_POSTFIX:STRING=d"
                               "-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=OLD"
                               "-DCMAKE_C_FLAGS_DEBUG:STRING=/MTd /Zi /Ob0 /Od /RTC1"
                               "-DCMAKE_C_FLAGS_RELEASE:STRING=/MT /O2 /Ob2 /DNDEBUG")
   
   # Explicitly disable tests to prevent non-postfixed lib creation
   set(_config_options "-DENABLE_CUSTOM_COMPILER_FLAGS:BOOL=OFF"
                       "-DENABLE_CJSON_TEST:BOOL=OFF")
   
   # Manual install with explicit targets and cleanup
   set( _EPA_INSTALL_COMMAND 
       "INSTALL_COMMAND    \"${CMAKE_COMMAND}\"   --build .  --config Debug --target cjson"
       "        COMMAND    \"${CMAKE_COMMAND}\" -E remove -f Debug/cjson.lib"
       "        COMMAND    \"${CMAKE_COMMAND}\" -E make_directory <INSTALL_DIR>/include/cjson"
       "        COMMAND    \"${CMAKE_COMMAND}\" -E make_directory <INSTALL_DIR>/lib"
       "        COMMAND    \"${CMAKE_COMMAND}\" -E copy_if_different cJSON.h <INSTALL_DIR>/include/cjson/"
       "        COMMAND    \"${CMAKE_COMMAND}\" -E copy_if_different Debug/cjsond.lib <INSTALL_DIR>/lib/cjsond.lib"
       "        COMMAND    \"${CMAKE_COMMAND}\"   --build .  --config Release --target cjson"
       "        COMMAND    \"${CMAKE_COMMAND}\" -E copy_if_different Release/cjson.lib <INSTALL_DIR>/lib/cjson.lib")
   ```

2. **In `rebuild_static_crt.ps1`** (already implemented):
   ```powershell
   & $CMAKE `
       -G "Visual Studio 17 2022" -A x64 `
       -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
       -DCMAKE_MSVC_RUNTIME_LIBRARY="`$<`$<CONFIG:Debug>:MultiThreadedDebug>`$<`$<CONFIG:Release>:MultiThreaded>" `
       -DBUILD_SHARED_LIBS=OFF `
       -DCMAKE_INSTALL_PREFIX="$REPO_ROOT\install" `
       -DCMAKE_DEBUG_POSTFIX=d `
       -DENABLE_CJSON_TEST:BOOL=OFF `
       -DENABLE_CUSTOM_COMPILER_FLAGS:BOOL=OFF `
       .
   ```

3. **Verify the fix:**
   ```powershell
   # Check Debug folder has ONLY cjsond.lib
   Get-ChildItem "external\BUILD\cjson\source\Debug\*.lib"
   # Expected: Only cjsond.lib (no cjson.lib, no cJSON_test.lib)
   
   # Check Release folder has ONLY cjson.lib
   Get-ChildItem "external\BUILD\cjson\source\Release\*.lib"
   # Expected: Only cjson.lib (no cjsond.lib, no cJSON_test.lib)
   
   # Verify CRT in installed libraries
   $DUMPBIN = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
   & $DUMPBIN /directives install\lib\cjson.lib | Select-String "DEFAULTLIB:LIBCMT"
   # Expected: /DEFAULTLIB:LIBCMT (Release - static CRT)
   
   & $DUMPBIN /directives install\lib\cjsond.lib | Select-String "DEFAULTLIB:LIBCMT"
   # Expected: /DEFAULTLIB:LIBCMTD (Debug - static CRT)
   ```

4. **Use diagnostic monitoring** (included in `rebuild_static_crt.ps1`):
   - The script now includes color-coded monitoring that shows Debug and Release folder contents after each build stage
   - Red errors highlight when wrong files appear in wrong folders
   - This helps identify exactly which build step is causing issues

**Key Points:**
- **Always disable tests** when building cjson (`-DENABLE_CJSON_TEST:BOOL=OFF`)
- **Use explicit targets** (`--target cjson`) to build only the main library
- **Clean up** any non-postfixed files after Debug build
- **Manual copy** ensures correct files are installed, not whatever the install target decides
- **DEBUG_POSTFIX works** when combined with `CMP0091=OLD` and direct C_FLAGS

**Technical Background:**

The cjson project creates multiple targets:
- `cjson` (main library) - respects DEBUG_POSTFIX → creates `cjsond.lib` in Debug
- `cjson_test` (test library) - does NOT respect DEBUG_POSTFIX → creates `cjson.lib` even in Debug
- `cJSON_test` (test executable) - also creates `cJSON_test.lib`

When tests are enabled, the test library overwrites or conflicts with the intended output. The fix ensures only the main `cjson` target is built, and explicitly removes any stray `Debug/cjson.lib` files before copying to the install directory.

---

## Quick Reference

**One-liner to regenerate solution and build (after cleanup):**
```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
mkdir build -ErrorAction SilentlyContinue
cd build
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" -G "Visual Studio 17 2022" -A x64 -DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -Dlibxml2_USE_INSTALLED:BOOL=OFF -DBUILD_RTSDK-BINARYPACK:BOOL=OFF -DRTSDK_OPT_BUILD_ETA_EMA_LIBRARIES:BOOL=ON -DBUILD_UNIT_TESTS:BOOL=OFF -DBUILD_ETA_EXAMPLES:BOOL=OFF -DBUILD_EMA_EXAMPLES:BOOL=OFF -DBUILD_EMA_DOXYGEN:BOOL=OFF -DBUILD_ETA_TRAINING:BOOL=OFF -DBUILD_ETA_PERFTOOLS:BOOL=OFF ..
cd ..
& "C:\Program Files\Microsoft Visual Studio\2022\Comm, zlib, lz4) to confirm static CRT
4. ✓ Verify external CRT with dumpbin
5. ✓ Verify SDK static libraries (librssl.lib) for mixed CRT, rebuild if needed
6. ✓ Consolidate l8w8jwt + mbedtls into single lib
7. ✓ Build SDK via MSBuild
8
## Summary

This guide walks through a full static CRT build on Windows (VS2022, x64, Debug_Mdd and Release_MD):

1. ✓ Clean old artifacts
2. ✓ Generate VS solution with CMake (static CRT options applied via generator expressions)
3. ✓ Rebuild key externals (ccronexpr, cjson, l8w8jwt, zlib, lz4) for Debug and Release
4. ✓ Verify CRT with dumpbin (LIBCMTD for Debug, LIBCMT for Release)
5. ✓ Consolidate l8w8jwt + mbedtls into single lib (Debug and Release variants)
6. ✓ Build SDK via MSBuild (both Debug_Mdd and Release_MD)
7. ✓ Verify .dll output artifacts for both configurations

**Result:** Clean Debug_Mdd and Release_MD x64 builds with zero unresolved symbols and all externals using `/MTd` (Debug) or `/MT` (Release) static CRT.

---

## Change Log

### April 13, 2026 - cjson Build Fixes

**Issues Resolved:**
- Fixed cjson libraries having wrong CRT (Debug library `cjson.lib` had `/DEFAULTLIB:LIBCMTD` instead of `/DEFAULTLIB:LIBCMT`)
- Eliminated duplicate/wrong files in Debug and Release folders (Debug folder was creating both `cjson.lib` and `cjsond.lib`)
- Test builds creating non-postfixed libraries that conflicted with DEBUG_POSTFIX

**Changes Made:**

1. **`CMake/addExternal_cjson.cmake`:**
   - Changed from `CMP0091=NEW` to `CMP0091=OLD` for more reliable CRT control with direct C_FLAGS
   - Added explicit `-DENABLE_CJSON_TEST:BOOL=OFF` to disable test builds
   - Changed install command from `--target install` to manual file copying with specific targets
   - Added `cmake -E remove -f Debug/cjson.lib` cleanup step to remove any stray non-postfixed files
   - Specified `--target cjson` for both Debug and Release builds to avoid building test targets

2. **`rebuild_static_crt.ps1`:**
   - Added `-DCMAKE_DEBUG_POSTFIX=d` to ensure debug suffix
   - Added `-DENABLE_CJSON_TEST:BOOL=OFF` to match CMake configuration
   - Added `-DENABLE_CUSTOM_COMPILER_FLAGS:BOOL=OFF` to prevent cjson from overriding compiler flags
   - Implemented comprehensive diagnostic monitoring with color-coded output showing:
     - Debug and Release folder contents after each build stage
     - File sizes and timestamps for each library
     - Red error alerts when wrong files appear in wrong locations
     - Green success messages when files are in correct locations

3. **Documentation Updates:**
   - Added new troubleshooting section: "cjson libraries have wrong CRT or wrong files in Debug/Release folders"
   - Updated "Rebuild cjson" example with correct configuration flags
   - Added "Automated Build Script" section documenting the diagnostic monitoring features
   - Included technical background explaining cjson's multiple targets (cjson, cjson_test, cJSON_test)

**Impact:**
- cjson Debug builds now correctly create only `cjsond.lib` with `/DEFAULTLIB:LIBCMTD`
- cjson Release builds now correctly create only `cjson.lib` with `/DEFAULTLIB:LIBCMT`
- No more mixed CRT or duplicate files
- Diagnostic output makes troubleshooting much easier for future issues

---

## Additional Resources

- [CMake `CMAKE_MSVC_RUNTIME_LIBRARY` documentation](https://cmake.org/cmake/help/latest/variable/CMAKE_MSVC_RUNTIME_LIBRARY.html)
- [CMake Policy `CMP0091`](https://cmake.org/cmake/help/latest/policy/CMP0091.html)
- Real-Time SDK CMake modules: `CMake/rcdevCommonUtils.cmake`, `CMake/addExternal_*.cmake`
