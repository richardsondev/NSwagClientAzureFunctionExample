# Use the Microsoft provided `Get-OpenApiDocument.ps1` to start the Azure function
# and extract the swagger.json. Finally, invoke NSwag on the exported swagger.json
# to generate a C# and TypeScript client.

# Configurations
# Azure Functions Core Tools config
$funcToolsUrl = "https://github.com/Azure/azure-functions-core-tools/releases/download/4.0.5455/Azure.Functions.Cli.win-x64.4.0.5455.zip"
$funcToolsSha512 = "7b75f5b2e35990434eafd4b56e125d3e78dd79a524e47c556cab11f21d250901e59a9f37dd8dd6220d27e52ef89d6e0ebdf4444a450f4cbb5b6ff36776af96e9"

# Azure Functions OpenAPI helper script config
$openApiSwaggerScriptUrl = "https://raw.githubusercontent.com/Azure/azure-functions-openapi-extension/238a039c257e033a6049586410da4666412cd875/actions/Get-OpenApiDocument.ps1"
$openApiSwaggerScriptSha512 = "d3361ab279a5050db5ccc3697b8126c527691faca6490bc2b983c7719d3fea7b9225720d0496627ef46ae350010d5dc2415b09dac42b14cf3828cfea662f5cb6"

# NSwag config
$nswagZipUrl = "https://github.com/RicoSuter/NSwag/releases/download/v14.0.1/NSwag.zip"
$nswagSha512 = "8ab9001c1ad0382300bc3e8507789129d9e5f1887c5eb9dcdeb99d27cfb80f3881f22e7ce41cb51be36127e4cf727dcf8b47d7f364f3228c0ec395c98c891441"
$nswagBinary = "Net70\dotnet-nswag.exe"
$defaultNSwagPath = Join-Path (Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)) "Rico Suter\NSwagStudio\") $nswagBinary

# Define the input and output paths
$rootProject = Split-Path -Path $PSScriptRoot -Parent
$generatedPath = Join-Path $rootProject "generated"
$inputSwaggerJson = Join-Path $generatedPath "swagger.json"
$functionAppPath = "bin\Debug\net7.0"

# Function to create a temporary directory
function New-TemporaryDirectory {
    $tempFolder = [System.IO.Path]::GetTempFileName()
    Remove-Item $tempFolder
    return New-Item -Path $tempFolder -ItemType Directory
}

# Function to download and verify a file
function Download-AndVerifyFile {
    param ($url, $destination, $expectedSha512)
    Invoke-WebRequest -Uri $url -OutFile $destination
    $computedHash = Get-FileSha512Hash $destination
    if ($computedHash -ne $expectedSha512.ToLower()) {
        throw "Checksum verification failed. The downloaded file may be corrupted or tampered with. Received: $computedHash Expected: $expectedSha512"
    }
}

# Function to calculate SHA512 hash of a file
function Get-FileSha512Hash {
    param ($filePath)
    $fileStream = [System.IO.File]::OpenRead($filePath)
    $sha512 = [System.Security.Cryptography.SHA512]::Create()
    $computedHash = [BitConverter]::ToString($sha512.ComputeHash($fileStream)).Replace("-", "").ToLower()
    $fileStream.Close()
    return $computedHash
}

# Function to extract a ZIP file
function Extract-ZipFile {
    param ($zipPath, $destination)
    Expand-Archive -Path $zipPath -DestinationPath $destination
}

# Function to download and setup Azure Functions Core Tools
function Setup-AzureFunctionsCoreTools {
    param ($tempFolder)
    $tempFunctionFolder = Join-Path $tempFolder "coretools"
    New-Item -Path $tempFunctionFolder -ItemType Directory | Out-Null
    $zipPath = Join-Path $tempFunctionFolder "AzureFunctionsCli.zip"
    Download-AndVerifyFile -url $funcToolsUrl -destination $zipPath -expectedSha512 $funcToolsSha512
    Extract-ZipFile -zipPath $zipPath -destination $tempFunctionFolder
    $env:Path += ";$tempFunctionFolder"
}

# Function to download and setup NSwag
function Setup-NSwag {
    param ($tempFolder, $nswagBinary, $nswagZipUrl, $nswagSha512)
    $tempNSwagFolder = Join-Path $tempFolder "nswag"
    New-Item -Path $tempNSwagFolder -ItemType Directory | Out-Null
    $zipPath = Join-Path $tempNSwagFolder "NSwag.zip"
    Download-AndVerifyFile -url $nswagZipUrl -destination $zipPath -expectedSha512 $nswagSha512
    Extract-ZipFile -zipPath $zipPath -destination $tempNSwagFolder
    $nswagLocation = Join-Path $tempNSwagFolder $nswagBinary
    return $nswagLocation
}

# Function to run NSwag
function Run-NSwag {
    param ($nswagExe, $nswagConfigFile, $generatedPath, $inputSwaggerJson)

    # Check if the NSwag executable exists
    if (-not (Test-Path $nswagExe)) {
        throw "NSwag executable not found at path: $nswagExe"
    }

    # Ensure the .nswag file exists
    if (-not (Test-Path $nswagConfigFile)) {
        throw ".nswag configuration file not found at path: $nswagConfigFile"
    }

    &$nswagExe run $nswagConfigFile /variables:GeneratedPath="$generatedPath",InputSwaggerJson="$inputSwaggerJson"
}

# Main script starts here

# Create a temporary folder
$tempFolder = New-TemporaryDirectory

# Use try-finally to ensure cleanup
try {
    # Remove existing generated files
    Remove-Item $generatedPath -Recurse -Force -ErrorAction "SilentlyContinue"

    # Check if Azure Functions Core Tools is installed
    $azureFuncTools = Get-Command func -ErrorAction SilentlyContinue

    if ($null -eq $azureFuncTools) {
        Write-Output "Setting up Azure Function Core Tools"
        Setup-AzureFunctionsCoreTools -tempFolder $tempFolder.FullName
    }

    # Run the function and extract the swagger.json
    $scriptPath = Join-Path $tempFolder "Get-OpenApiDocument.ps1"
    Write-Output "Running $scriptPath"
    Download-AndVerifyFile -url $openApiSwaggerScriptUrl -destination $scriptPath -expectedSha512 $openApiSwaggerScriptSha512
    $env:GITHUB_WORKSPACE=$rootProject
    & $scriptPath -FunctionAppPath $functionAppPath

    # Ensure the .nswag file exists
    if (-not (Test-Path $inputSwaggerJson)) {
        throw "swagger.json file not found at path: $inputSwaggerJson"
    } else {
        Write-Output "swagger.json generated"
    }

    $nswagExe = $defaultNSwagPath

    if (-not (Test-Path $nswagExe)) {
        $nswagExe = (Setup-NSwag -tempFolder $tempFolder.FullName -nswagBinary $nswagBinary -nswagZipUrl $nswagZipUrl -nswagSha512 $nswagSha512)
    }

    # Define the path to the .nswag file
    $nswagConfigFile = Join-Path $PSScriptRoot "nswag.json"

    # Run NSwag with the .nswag configuration file
    Write-Output "Launching NSwag at $nswagExe"
    Run-NSwag -nswagExe $nswagExe -nswagConfigFile $nswagConfigFile -generatedPath $generatedPath -inputSwaggerJson $inputSwaggerJson

    # Output success message
    Write-Host "NSwag execution completed successfully."
} catch {
    # Output error message
    Write-Error "An error occurred: $_"
} finally {
    # Clean up the temporary folder
    Remove-Item $tempFolder -Recurse -Force
}
