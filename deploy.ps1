param(
    [ValidateSet('standard', 'private')]
    [string]$Profile = 'standard',
    [switch]$InfraOnly,
    [switch]$AppOnly
)

$profileMap = @{
    standard = 'infra'
    private  = 'infra-private'
}

$infraFolder    = $profileMap[$Profile]
$parametersFile = "$PSScriptRoot/$infraFolder/parameters.json"

if (-not (Test-Path $parametersFile)) {
    Write-Error "Parameters file not found: $parametersFile"
    exit 1
}

$params       = Get-Content $parametersFile -Raw | ConvertFrom-Json
$resourceGroup = $params.resourceGroup
$environment   = $params.environment
$appName       = $params.appName

if (-not $resourceGroup -or -not $environment -or -not $appName) {
    Write-Error "parameters.json must contain resourceGroup, environment, and appName."
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor DarkCyan
Write-Host " Profile      : $Profile"                -ForegroundColor Cyan
Write-Host " Resource group: $resourceGroup"         -ForegroundColor Cyan
Write-Host " App name      : $appName"               -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor DarkCyan
Write-Host ""

# ─── Infrastructure ────────────────────────────────────────────────────────────

if (-not $AppOnly) {
    Write-Host "Deploying infrastructure ($infraFolder)..." -ForegroundColor Cyan

    az group create --name $resourceGroup --location australiaeast --output none

    az deployment group create `
        --resource-group $resourceGroup `
        --template-file "$PSScriptRoot/$infraFolder/main.bicep" `
        --parameters environment=$environment

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Infrastructure deployment failed."
        exit 1
    }

    Write-Host "Infrastructure deployed." -ForegroundColor Green
}

# ─── App ───────────────────────────────────────────────────────────────────────

if (-not $InfraOnly) {
    $publishDir = "$PSScriptRoot/backend/publish"
    $zipPath    = "$PSScriptRoot/backend/app.zip"

    Write-Host "Publishing backend..." -ForegroundColor Cyan
    dotnet publish "$PSScriptRoot/backend" --configuration Release --output $publishDir

    if ($LASTEXITCODE -ne 0) {
        Write-Error "dotnet publish failed."
        exit 1
    }

    Write-Host "Zipping output..." -ForegroundColor Cyan
    Compress-Archive -Path "$publishDir/*" -DestinationPath $zipPath -Force

    Write-Host "Deploying app to $appName..." -ForegroundColor Cyan
    az webapp deploy `
        --resource-group $resourceGroup `
        --name $appName `
        --src-path $zipPath `
        --type zip

    if ($LASTEXITCODE -ne 0) {
        Write-Error "App deployment failed."
        exit 1
    }

    Write-Host "App deployed." -ForegroundColor Green
}

Write-Host ""
Write-Host "All done." -ForegroundColor Green
