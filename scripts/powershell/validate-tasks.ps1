#!/usr/bin/env pwsh

# Task structure validation script (PowerShell)
#
# Validates the tasks/ directory structure for consistency:
# - JSONL validity (each line is valid JSON)
# - File references (each file in JSONL exists)
# - No orphan files (no task files without JSONL entry)
# - Frontmatter sync (task file metadata matches JSONL)
# - Dependency validity (all depends_on refs exist, no cycles)
# - Status coherence (done tasks have all dependencies done)
#
# Usage: ./validate-tasks.ps1 [OPTIONS]
#
# OPTIONS:
#   -Json       Output results in JSON format
#   -Verbose    Show detailed information for each check
#   -Help       Show help message

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Verbose,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Show help if requested
if ($Help) {
    Write-Output @"
Usage: validate-tasks.ps1 [OPTIONS]

Validates the tasks/ directory structure for consistency.

OPTIONS:
  -Json       Output results in JSON format
  -Verbose    Show detailed information for each check
  -Help       Show this help message

CHECKS PERFORMED:
  1. JSONL validity - Each line in tasks.jsonl is valid JSON
  2. File references - Each file referenced in JSONL exists
  3. No orphans - No task files exist without JSONL entry
  4. Frontmatter sync - Task file frontmatter matches JSONL data
  5. Dependency validity - All depends_on refs exist, no cycles
  6. Status coherence - Done tasks have all dependencies done

EXIT CODES:
  0 - All checks passed
  1 - One or more checks failed
  2 - Tasks directory not found

"@
    exit 0
}

# Source common functions
. "$PSScriptRoot/common.ps1"

# Get feature paths
$paths = Get-FeaturePathsEnv

$TasksDir = $paths.TASKS_DIR
$TasksIndex = $paths.TASKS_INDEX

# Check if tasks directory exists
if (-not (Test-Path $TasksDir -PathType Container)) {
    if ($Json) {
        Write-Output '{"valid":false,"error":"Tasks directory not found","checks":[]}'
    } else {
        Write-Error "ERROR: Tasks directory not found: $TasksDir"
        Write-Output "Run /speckit.tasks first to create the task structure."
    }
    exit 2
}

# Check if tasks.jsonl exists
if (-not (Test-Path $TasksIndex -PathType Leaf)) {
    if ($Json) {
        Write-Output '{"valid":false,"error":"tasks.jsonl not found","checks":[]}'
    } else {
        Write-Error "ERROR: tasks.jsonl not found: $TasksIndex"
        Write-Output "Run /speckit.tasks first to create the task structure."
    }
    exit 2
}

# Initialize validation results
$Errors = @()
$Warnings = @()
$ChecksPassed = 0
$ChecksFailed = 0

function Add-Error {
    param([string]$Message)
    $script:Errors += $Message
    $script:ChecksFailed++
}

function Add-Warning {
    param([string]$Message)
    $script:Warnings += $Message
}

function Add-Pass {
    param([string]$Message)
    $script:ChecksPassed++
    if ($Verbose -and -not $Json) {
        Write-Output "  ✓ $Message"
    }
}

# ============================================================================
# Check 1: JSONL Validity
# ============================================================================
if ($Verbose -and -not $Json) {
    Write-Output "Checking JSONL validity..."
}

$LineNum = 0
$Tasks = @()

Get-Content $TasksIndex | ForEach-Object {
    $LineNum++
    $line = $_

    # Skip empty lines
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    # Validate JSON
    try {
        $task = $line | ConvertFrom-Json

        if (-not $task.id) {
            Add-Error "Line $LineNum`: Missing 'id' field"
            return
        }

        if (-not $task.file) {
            Add-Error "Line $LineNum`: Missing 'file' field for task $($task.id)"
            return
        }

        $Tasks += [PSCustomObject]@{
            id = $task.id
            file = $task.file
            status = $task.status
            depends_on = $task.depends_on
        }
    }
    catch {
        Add-Error "Line $LineNum`: Invalid JSON"
    }
}

if ($LineNum -eq 0) {
    Add-Error "tasks.jsonl is empty"
} else {
    Add-Pass "JSONL validity: $LineNum lines parsed"
}

# ============================================================================
# Check 2: File References
# ============================================================================
if ($Verbose -and -not $Json) {
    Write-Output "Checking file references..."
}

foreach ($task in $Tasks) {
    $taskFile = Join-Path $TasksDir $task.file
    if (-not (Test-Path $taskFile -PathType Leaf)) {
        Add-Error "Task $($task.id): Referenced file not found: $($task.file)"
    } else {
        Add-Pass "Task $($task.id): File exists"
    }
}

# ============================================================================
# Check 3: No Orphan Files
# ============================================================================
if ($Verbose -and -not $Json) {
    Write-Output "Checking for orphan files..."
}

$referencedFiles = $Tasks | ForEach-Object { $_.file }

Get-ChildItem -Path $TasksDir -Filter "T*.md" -File | ForEach-Object {
    $filename = $_.Name
    if ($filename -notin $referencedFiles) {
        Add-Error "Orphan file (not in tasks.jsonl): $filename"
    }
}

Add-Pass "Orphan check complete"

# ============================================================================
# Check 4: Frontmatter Sync
# ============================================================================
if ($Verbose -and -not $Json) {
    Write-Output "Checking frontmatter sync..."
}

foreach ($task in $Tasks) {
    $taskFile = Join-Path $TasksDir $task.file
    if (-not (Test-Path $taskFile -PathType Leaf)) { continue }

    $content = Get-Content $taskFile -Raw

    # Extract frontmatter
    if ($content -match '(?s)^---\r?\n(.*?)\r?\n---') {
        $frontmatter = $Matches[1]

        # Extract id
        if ($frontmatter -match '(?m)^id:\s*(.+)$') {
            $fmId = $Matches[1].Trim()
            if ($fmId -ne $task.id) {
                Add-Error "Task $($task.id): Frontmatter id mismatch (found: '$fmId')"
            } else {
                Add-Pass "Task $($task.id): Frontmatter sync OK"
            }
        }

        # Extract status
        if ($frontmatter -match '(?m)^status:\s*(.+)$') {
            $fmStatus = $Matches[1].Trim()
            if ($fmStatus -ne $task.status) {
                Add-Warning "Task $($task.id): Status mismatch (JSONL: '$($task.status)', file: '$fmStatus')"
            }
        }
    }
}

# ============================================================================
# Check 5: Dependency Validity
# ============================================================================
if ($Verbose -and -not $Json) {
    Write-Output "Checking dependency validity..."
}

$taskIds = $Tasks | ForEach-Object { $_.id }

# Check all deps exist
foreach ($task in $Tasks) {
    if (-not $task.depends_on) { continue }

    foreach ($dep in $task.depends_on) {
        if ($dep -notin $taskIds) {
            Add-Error "Task $($task.id): Unknown dependency '$dep'"
        }
    }
}

# Check for cycles (simple DFS)
function Test-Cycle {
    param(
        [string]$TaskId,
        [string[]]$Visiting
    )

    # Check if already visiting (cycle)
    if ($TaskId -in $Visiting) {
        return $true
    }

    $task = $Tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if (-not $task -or -not $task.depends_on) {
        return $false
    }

    $newVisiting = $Visiting + $TaskId

    foreach ($dep in $task.depends_on) {
        if (Test-Cycle -TaskId $dep -Visiting $newVisiting) {
            return $true
        }
    }

    return $false
}

foreach ($task in $Tasks) {
    if (Test-Cycle -TaskId $task.id -Visiting @()) {
        Add-Error "Circular dependency detected involving task $($task.id)"
    }
}

Add-Pass "Dependency check complete"

# ============================================================================
# Check 6: Status Coherence
# ============================================================================
if ($Verbose -and -not $Json) {
    Write-Output "Checking status coherence..."
}

foreach ($task in $Tasks) {
    if ($task.status -ne 'done') { continue }
    if (-not $task.depends_on) { continue }

    foreach ($dep in $task.depends_on) {
        $depTask = $Tasks | Where-Object { $_.id -eq $dep } | Select-Object -First 1
        if ($depTask -and $depTask.status -ne 'done') {
            Add-Warning "Task $($task.id) is done but dependency $dep is not"
        }
    }
}

Add-Pass "Status coherence check complete"

# ============================================================================
# Output Results
# ============================================================================
$Valid = $Errors.Count -eq 0

if ($Json) {
    $result = [PSCustomObject]@{
        valid = $Valid
        tasks = $Tasks.Count
        checks_passed = $ChecksPassed
        checks_failed = $ChecksFailed
        errors = $Errors
        warnings = $Warnings
    }
    $result | ConvertTo-Json -Compress
} else {
    Write-Output ""
    Write-Output "=== Validation Results ==="
    Write-Output "Tasks: $($Tasks.Count)"
    Write-Output "Checks passed: $ChecksPassed"
    Write-Output "Checks failed: $ChecksFailed"
    Write-Output ""

    if ($Errors.Count -gt 0) {
        Write-Output "Errors:"
        foreach ($err in $Errors) {
            Write-Output "  ✗ $err"
        }
        Write-Output ""
    }

    if ($Warnings.Count -gt 0) {
        Write-Output "Warnings:"
        foreach ($warn in $Warnings) {
            Write-Output "  ⚠ $warn"
        }
        Write-Output ""
    }

    if ($Valid) {
        Write-Output "✓ All checks passed"
    } else {
        Write-Output "✗ Validation failed"
    }
}

if ($Valid) { exit 0 } else { exit 1 }
