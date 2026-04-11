<#
.SYNOPSIS
    Automatically applies static CRT (CMAKE_POLICY_DEFAULT_CMP0091) fixes to CMake external library files.

.DESCRIPTION
    This script programmatically modifies 6 CMake addExternal_*.cmake files to add the 
    CMAKE_POLICY_DEFAULT_CMP0091=NEW policy, which is required for CMAKE_MSVC_RUNTIME_LIBRARY
    to work correctly with external projects.
    
    The script:
    1. Creates backups of all files before modification
    2. Searches for the appropriate insertion point in each file
    3. Adds the CMP0091 policy line (and MSVC_RUNTIME_LIBRARY if missing)
    4. Verifies the changes were applied correctly
    5. Can restore from backups if needed

.PARAMETER RestoreBackups
    Restore all files from their .backup versions

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\apply_static_crt_fixes.ps1
    Applies all fixes with confirmation

.EXAMPLE
    .\apply_static_crt_fixes.ps1 -Force
    Applies all fixes without confirmation

.EXAMPLE
    .\apply_static_crt_fixes.ps1 -RestoreBackups
    Restores all files from backups

.NOTES
    Author: GitHub Copilot
    Date: 2025-12-18
    This script fixes the issue where external libraries were built with MSVCRT (dynamic CRT)
    instead of LIBCMT (static CRT) despite CMAKE_MSVC_RUNTIME_LIBRARY being set.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Restore files from backups instead of applying fixes")]
    [switch]$RestoreBackups,
    
    [Parameter(HelpMessage="Skip confirmation prompts")]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration
$WorkspaceRoot = $PSScriptRoot
$CMakeDir = Join-Path $WorkspaceRoot "CMake"

# Define the files to modify and their specific modifications
$FilesToModify = @(
    @{
        Name = "addExternal_zlib.cmake"
        Path = Join-Path $CMakeDir "addExternal_zlib.cmake"
        SearchPattern = '^\s*if\s*\(\s*WIN32\s*\)'
        SearchContext = 'list(APPEND _config_options "-DCMAKE_DEBUG_POSTFIX'
        InsertAfter = 'list(APPEND _config_options "-DCMAKE_DEBUG_POSTFIX:STRING=d"'
        LinesToAdd = @(
            '									"-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW"',
            '									"-DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=${CMAKE_MSVC_RUNTIME_LIBRARY_FOR_EXTERNAL}"'
        )
        Description = "zlib - Add CMP0091 policy and MSVC_RUNTIME_LIBRARY"
    },
    @{
        Name = "addExternal_lz4.cmake"
        Path = Join-Path $CMakeDir "addExternal_lz4.cmake"
        SearchPattern = '^\s*if\s*\(\s*WIN32\s*\)'
        SearchContext = 'list(APPEND _config_options "-DCMAKE_DEBUG_POSTFIX'
        InsertAfter = 'list(APPEND _config_options "-DCMAKE_DEBUG_POSTFIX:STRING=d"'
        LinesToAdd = @(
            '									"-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW"',
            '									"-DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=${CMAKE_MSVC_RUNTIME_LIBRARY_FOR_EXTERNAL}"'
        )
        Description = "lz4 - Add CMP0091 policy and MSVC_RUNTIME_LIBRARY"
    },
    @{
        Name = "addExternal_cjson.cmake"
        Path = Join-Path $CMakeDir "addExternal_cjson.cmake"
        SearchPattern = '^\s*if\s*\(\s*WIN32\s*\)'
        SearchContext = 'list(APPEND _config_options "-DCMAKE_POLICY_DEFAULT_CMP0091'
        InsertAfter = 'list(APPEND _config_options "-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW"'
        LinesToAdd = @()  # Already has CMP0091 and MSVC_RUNTIME_LIBRARY
        Description = "cjson - Already has CMP0091 policy (no changes needed)"
        AlreadyFixed = $true
    },
    @{
        Name = "addExternal_ccron.cmake"
        Path = Join-Path $CMakeDir "addExternal_ccron.cmake"
        SearchPattern = '^\s*if\s*\(\s*WIN32\s*\)'
        SearchContext = 'list(APPEND _config_options "-DCMAKE_POLICY_DEFAULT_CMP0091'
        InsertAfter = 'list(APPEND _config_options "-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW"'
        LinesToAdd = @()  # Already has CMP0091 and MSVC_RUNTIME_LIBRARY
        Description = "ccronexpr - Already has CMP0091 policy (no changes needed)"
        AlreadyFixed = $true
    },
    @{
        Name = "addExternal_l8w8jwt.cmake"
        Path = Join-Path $CMakeDir "addExternal_l8w8jwt.cmake"
        SearchPattern = '^\s*if\s*\(\s*WIN32\s*\)'
        SearchContext = 'list(APPEND _config_options "-DCMAKE_POLICY_DEFAULT_CMP0091'
        InsertAfter = 'list(APPEND _config_options "-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW"'
        LinesToAdd = @()  # Already has CMP0091 and MSVC_RUNTIME_LIBRARY
        Description = "l8w8jwt - Already has CMP0091 policy (no changes needed)"
        AlreadyFixed = $true
    },
    @{
        Name = "addExternal_curl.cmake"
        Path = Join-Path $CMakeDir "addExternal_curl.cmake"
        SearchPattern = '^\s*if\s*\(\s*WIN32\s*\)'
        SearchContext = 'set\(_config_options "\$\{_config_options\}"'
        InsertAfter = 'set(_config_options "${_config_options}"'
        InsertBefore = '						"-DCURL_USE_SCHANNEL:BOOL=ON"'
        LinesToAdd = @(
            '						"-DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW"',
            '						"-DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=${CMAKE_MSVC_RUNTIME_LIBRARY_FOR_EXTERNAL}"'
        )
        Description = "curl - Add CMP0091 policy and MSVC_RUNTIME_LIBRARY"
        InsertBeforeMode = $true
    }
)

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Test-FileAlreadyFixed {
    param(
        [string]$FilePath,
        [string]$SearchText
    )
    
    $content = Get-Content $FilePath -Raw
    return $content -match [regex]::Escape($SearchText)
}

function Backup-File {
    param(
        [string]$FilePath
    )
    
    $backupPath = "$FilePath.backup"
    if (Test-Path $backupPath) {
        Write-ColorOutput "  Backup already exists: $backupPath" Yellow
    } else {
        Copy-Item $FilePath $backupPath -Force
        Write-ColorOutput "  Created backup: $backupPath" Green
    }
}

function Restore-FromBackup {
    param(
        [string]$FilePath
    )
    
    $backupPath = "$FilePath.backup"
    if (Test-Path $backupPath) {
        Copy-Item $backupPath $FilePath -Force
        Write-ColorOutput "  Restored from backup: $FilePath" Green
        return $true
    } else {
        Write-ColorOutput "  No backup found: $backupPath" Yellow
        return $false
    }
}

function Apply-CMP0091Fix {
    param(
        [hashtable]$FileConfig
    )
    
    $filePath = $FileConfig.Path
    $fileName = $FileConfig.Name
    
    Write-ColorOutput "`n[$fileName]" Cyan
    Write-ColorOutput "  Description: $($FileConfig.Description)" Gray
    
    # Check if file exists
    if (-not (Test-Path $filePath)) {
        Write-ColorOutput "  ERROR: File not found!" Red
        return $false
    }
    
    # Check if already fixed
    if ($FileConfig.AlreadyFixed) {
        Write-ColorOutput "  Status: Already contains CMP0091 policy" Green
        return $true
    }
    
    # Check if CMP0091 already present
    if (Test-FileAlreadyFixed $filePath "CMAKE_POLICY_DEFAULT_CMP0091") {
        Write-ColorOutput "  Status: Already contains CMP0091 policy (skipping)" Green
        return $true
    }
    
    # Create backup
    Backup-File $filePath
    
    # Read file content
    $lines = Get-Content $filePath
    $modified = $false
    $newLines = @()
    
    # Find insertion point and add lines
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $newLines += $line
        
        # Check if this is the insertion point
        if (-not $modified) {
            if ($FileConfig.InsertBeforeMode) {
                # Insert BEFORE the matching line
                if ($line -match [regex]::Escape($FileConfig.InsertBefore)) {
                    Write-ColorOutput "  Found insertion point (before): Line $($i + 1)" Gray
                    # Remove the line we just added
                    $newLines = $newLines[0..($newLines.Count - 2)]
                    # Add new lines
                    foreach ($newLine in $FileConfig.LinesToAdd) {
                        $newLines += $newLine
                    }
                    # Add the original line back
                    $newLines += $line
                    $modified = $true
                }
            } else {
                # Insert AFTER the matching line
                if ($line -match [regex]::Escape($FileConfig.InsertAfter)) {
                    Write-ColorOutput "  Found insertion point (after): Line $($i + 1)" Gray
                    foreach ($newLine in $FileConfig.LinesToAdd) {
                        $newLines += $newLine
                    }
                    $modified = $true
                }
            }
        }
    }
    
    if (-not $modified) {
        Write-ColorOutput "  WARNING: Insertion point not found!" Yellow
        Write-ColorOutput "  Looking for: $($FileConfig.InsertAfter)" Yellow
        return $false
    }
    
    # Write modified content
    $newLines | Set-Content $filePath -Encoding UTF8
    Write-ColorOutput "  Status: Successfully modified" Green
    
    # Verify the change
    if (Test-FileAlreadyFixed $filePath "CMAKE_POLICY_DEFAULT_CMP0091") {
        Write-ColorOutput "  Verification: CMP0091 policy confirmed present" Green
        return $true
    } else {
        Write-ColorOutput "  ERROR: Verification failed!" Red
        return $false
    }
}

# Main execution
try {
    Write-ColorOutput "`n========================================" Cyan
    Write-ColorOutput "RTSDK Static CRT Auto-Fix Script" Cyan
    Write-ColorOutput "========================================`n" Cyan
    
    if ($RestoreBackups) {
        Write-ColorOutput "MODE: Restore from backups`n" Yellow
        
        if (-not $Force) {
            $response = Read-Host "This will restore all CMake files from backups. Continue? (y/n)"
            if ($response -ne 'y') {
                Write-ColorOutput "Cancelled by user." Yellow
                exit 0
            }
        }
        
        $restoredCount = 0
        foreach ($fileConfig in $FilesToModify) {
            Write-ColorOutput "`nRestoring: $($fileConfig.Name)" Cyan
            if (Restore-FromBackup $fileConfig.Path) {
                $restoredCount++
            }
        }
        
        Write-ColorOutput "`n========================================" Cyan
        Write-ColorOutput "Restored $restoredCount of $($FilesToModify.Count) files" $(if ($restoredCount -eq $FilesToModify.Count) { "Green" } else { "Yellow" })
        Write-ColorOutput "========================================`n" Cyan
        
    } else {
        Write-ColorOutput "MODE: Apply CMP0091 policy fixes`n" Cyan
        Write-ColorOutput "This script will modify the following files:" Gray
        foreach ($fileConfig in $FilesToModify) {
            $status = if ($fileConfig.AlreadyFixed) { " (already fixed)" } else { "" }
            Write-ColorOutput "  - $($fileConfig.Name)$status" Gray
        }
        
        if (-not $Force) {
            Write-ColorOutput "`nBackups will be created automatically (.backup extension)" Gray
            $response = Read-Host "`nContinue with modifications? (y/n)"
            if ($response -ne 'y') {
                Write-ColorOutput "Cancelled by user." Yellow
                exit 0
            }
        }
        
        Write-ColorOutput "`nApplying fixes...`n" Cyan
        
        $successCount = 0
        $skippedCount = 0
        $failedCount = 0
        
        foreach ($fileConfig in $FilesToModify) {
            if ($fileConfig.AlreadyFixed) {
                $skippedCount++
            }
            
            if (Apply-CMP0091Fix $fileConfig) {
                $successCount++
            } else {
                $failedCount++
            }
        }
        
        Write-ColorOutput "`n========================================" Cyan
        Write-ColorOutput "RESULTS" Cyan
        Write-ColorOutput "========================================" Cyan
        Write-ColorOutput "Total files: $($FilesToModify.Count)" Gray
        Write-ColorOutput "Successfully modified: $successCount" $(if ($successCount -gt 0) { "Green" } else { "Gray" })
        Write-ColorOutput "Already fixed (skipped): $skippedCount" Yellow
        Write-ColorOutput "Failed: $failedCount" $(if ($failedCount -gt 0) { "Red" } else { "Gray" })
        Write-ColorOutput "========================================`n" Cyan
        
        if ($failedCount -eq 0) {
            Write-ColorOutput "All fixes applied successfully!`n" Green
            Write-ColorOutput "Next steps:" Cyan
            Write-ColorOutput "1. Run: .\rebuild_static_crt.ps1" Gray
            Write-ColorOutput "2. Verify all external libs use LIBCMT (static CRT)" Gray
            Write-ColorOutput "3. Commit changes to git`n" Gray
            
            Write-ColorOutput "To restore original files, run:" Yellow
            Write-ColorOutput "  .\apply_static_crt_fixes.ps1 -RestoreBackups`n" Yellow
            
            exit 0
        } else {
            Write-ColorOutput "Some modifications failed. Review the errors above." Red
            Write-ColorOutput "Original files are backed up with .backup extension.`n" Yellow
            exit 1
        }
    }
    
} catch {
    Write-ColorOutput "`nERROR: $($_.Exception.Message)" Red
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" Red
    exit 1
}
