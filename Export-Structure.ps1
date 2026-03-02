<#
.SYNOPSIS
Scan directory and generate a structure.json and a standalone File Explorer HTML.

.DESCRIPTION
This script reads the structure of a given directory, generates a JSON representation (structure.json),
and then embeds that data into a standalone HTML file (OfflineExplorer.html) so you can send it to friends.
#>

$TargetFolder = Read-Host "Enter the path to scan (Press Enter for current directory)"
if ([string]::IsNullOrWhiteSpace($TargetFolder)) { $TargetFolder = "." }

try {
    $parentPath = (Resolve-Path $TargetFolder).Path
}
catch {
    Write-Host "Error: Cannot resolve path '$TargetFolder'. Please make sure the path exists." -ForegroundColor Red
    Pause
    exit
}

Write-Host "Please wait, scanning directory: $parentPath ..." -ForegroundColor Cyan

$items = Get-ChildItem -Path $parentPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $relPath = $_.FullName.Substring($parentPath.Length).TrimStart('\')
    $relPath = $relPath -replace '\\', '/'
    $parentFolder = ""
    if ($relPath.Contains('/')) {
        $parentFolder = $relPath.Substring(0, $relPath.LastIndexOf('/'))
    }
    
    [PSCustomObject]@{
        Name         = $_.Name
        Path         = $relPath
        ParentPath   = $parentFolder
        IsFolder     = $_.PSIsContainer
        Size         = if ($_.PSIsContainer) { $null } else { $_.Length }
        TotalSize    = 0
        FilesCount   = 0
        FoldersCount = 0
        DateModified = $_.LastWriteTime.ToString("M/d/yyyy h:mm tt")
    }
}

Write-Host "Found $($items.Count) items. Calculating folder sizes..." -ForegroundColor Cyan

$folderStats = @{}
foreach ($item in $items) {
    if ($item.IsFolder) {
        $folderStats[$item.Path] = @{ TotalSize = 0; FilesCount = 0; FoldersCount = 0 }
    }
}

foreach ($item in $items) {
    $parent = $item.ParentPath
    while ($parent -ne "") {
        if ($folderStats.ContainsKey($parent)) {
            if (-not $item.IsFolder) {
                $folderStats[$parent].TotalSize += $item.Size
                $folderStats[$parent].FilesCount += 1
            }
            else {
                $folderStats[$parent].FoldersCount += 1
            }
        }
        if ($parent.Contains('/')) {
            $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
        }
        else {
            $parent = ""
        }
    }
}

foreach ($item in $items) {
    if ($item.IsFolder) {
        $stats = $folderStats[$item.Path]
        $item.TotalSize = if ($null -eq $stats.TotalSize) { 0 } else { $stats.TotalSize }
        $item.FilesCount = $stats.FilesCount
        $item.FoldersCount = $stats.FoldersCount
    }
}

Write-Host "Processing data for HTML..." -ForegroundColor Cyan

# Prepare JSON
$jsonFormatted = @($items) | ConvertTo-Json -Depth 10
$jsonCompressed = @($items) | ConvertTo-Json -Depth 10 -Compress

# 1. Save standalone structure.json
$jsonOutPath = "$PSScriptRoot\structure.json"
$jsonFormatted | Out-File -FilePath $jsonOutPath -Encoding UTF8
Write-Host "1. Saved JSON File to: $jsonOutPath" -ForegroundColor Green

# 2. Embed into HTML Template to create Single-Page File Explorer
$templatePath = "$PSScriptRoot\explorer_template.html"
if (Test-Path $templatePath) {
    $htmlContent = [IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
    
    # Inject JSON directly into the Javascript variable
    $htmlContent = $htmlContent -replace 'const fileData = \[\];', "const fileData = $jsonCompressed;"
    
    $outHtml = "$PSScriptRoot\OfflineExplorer.html"
    [IO.File]::WriteAllText($outHtml, $htmlContent, [System.Text.Encoding]::UTF8)
    
    Write-Host "2. Saved Single-Page HTML Explorer to: $outHtml" -ForegroundColor Green
    Write-Host "`nSUCCESS! You can now just send 'OfflineExplorer.html' to your friends." -ForegroundColor Yellow
}
else {
    Write-Host "Warning: Template '$templatePath' not found. Only JSON was generated." -ForegroundColor Yellow
}

Write-Host "`nPress any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
