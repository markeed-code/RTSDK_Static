# Real-Time SDK: Static CRT Build Guide (Release_MD x64)

## Overview

This guide documents the process to build the Real-Time SDK (x64, Release_MD) with all externals statically linked against the MSVC runtime library (`/MT`). This eliminates CRT version conflicts and simplifies deployment.

### Problem Statement

Prior builds encountered unresolved linker errors due to mismatched CRT versions between externals and the SDK:
- Externals compiled with `/MD` (dynamic CRT)
- SDK targets `/MT` (static CRT)
- Result: unresolved symbol errors during linking of shared libraries (`librsslVA_shared`, `libema_shared`)

Additionally, `l8w8jwt` depends on mbedtls libraries, which must be properly linked into the consolidated external lib to avoid missing mbedtls symbols during final linking.

### Build Goals

✓ All externals use static CRT (`/DEFAULTLIB:LIBCMT`)  
✓ All mbedtls symbols bundled into `libl8w8jwt.lib`  
✓ Clean Release_MD x64 link of EMA and Eta shared libraries  
✓ Zero errors in final MSBuild step  

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
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded `
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
- CMake applies `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded` and `CMP0091=NEW` via `rcdevCommonUtils.cmake`, forcing static CRT

### 3. Rebuild Key Externals with Static CRT

The CMake configuration automatically configures externals with static CRT options. However, if needed, you can selectively rebuild an external:

**Example: Rebuild ccronexpr (Debug & Release)**
```powershell
cd c:\Users\marke\Reuters\RTSDK_GIT\Real-Time-SDK
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\ccronexpr\build --config Debug
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\ccronexpr\build --config Release
```

**Example: Rebuild cjson (Debug & Release)**
```powershell
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\cjson\build --config Debug
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build external\BUILD\cjson\build --config Release
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

2. **`CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`** in `CMake/rcdevCommonUtils.cmake`:
   - Passed to all externals via `CMAKE_MSVC_RUNTIME_LIBRARY_FOR_EXTERNAL`
   - Equivalent to `/MT` flag (static CRT, no debug info)

3. **Verification via `dumpbin /directives`**:
   - Shows `/DEFAULTLIB:LIBCMT` for static CRT
   - Shows `/DEFAULTLIB:MSVCRTD` or `/DEFAULTLIB:MSVCRT` if CRT mismatch remains

### l8w8jwt + mbedtls Consolidation

The external build script (`CMake/addExternal_l8w8jwt.cmake`):
- On Windows: uses the Library Manager to merge l8w8jwt.lib + mbedcrypto/mbedtls/mbedx509 into a single `libl8w8jwt.lib`
- On Linux: extracts object files and re-archives them
- This ensures the SDK linker resolves all mbedtls symbols from a single lib without missing dependency errors

---

## Troubleshooting

### External libraries built with dynamic CRT (MSVCRT) instead of static CRT (LIBCMT)

**Cause:** CMake not enforcing static CRT on external projects.  
**Solution:**
1. Ensure the CMake command includes these critical flags:
   - `-DCMAKE_POLICY_DEFAULT_CMP0091=NEW`
   - `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`
2. These flags MUST be passed at the top-level CMake configuration (Step 2)
3. Clean all artifacts (Step 1) and re-run CMake configuration
4. Verify rebuilt libs with `dumpbin /directives install\lib\*.lib | Select-String "DEFAULTLIB"`

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

### MSBuild fails mid-solution

**Cause:** Incomplete external builds or cache issues.  
**Solution:**
1. Clean the build directory: `Remove-Item -Recurse -Force build`
2. Re-run CMake configuration (step 2)
3. Re-run MSBuild (step 6)

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

This guide walks through a full static CRT build on Windows (VS2022, x64, Release_MD):

1. ✓ Clean old artifacts
2. ✓ Generate VS solution with CMake (static CRT options applied)
3. ✓ Rebuild key externals (ccronexpr, cjson, l8w8jwt) to confirm static CRT
4. ✓ Verify CRT with dumpbin
5. ✓ Consolidate l8w8jwt + mbedtls into single lib
6. ✓ Build SDK via MSBuild
7. ✓ Verify .dll output artifacts

**Result:** Clean Release_MD x64 build with zero unresolved symbols and all externals using `/MT` (static CRT).

---

## Additional Resources

- [CMake `CMAKE_MSVC_RUNTIME_LIBRARY` documentation](https://cmake.org/cmake/help/latest/variable/CMAKE_MSVC_RUNTIME_LIBRARY.html)
- [CMake Policy `CMP0091`](https://cmake.org/cmake/help/latest/policy/CMP0091.html)
- Real-Time SDK CMake modules: `CMake/rcdevCommonUtils.cmake`, `CMake/addExternal_*.cmake`
