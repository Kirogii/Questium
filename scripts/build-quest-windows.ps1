param(
    [string]$SourceApk = 'D:\VR Kommiku\artifacts\VR-Komikku-Frosted-Quest.apk',
    [string]$OutputApk = 'D:\VR Kommiku\VR-Komikku-Quest-current.apk'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path $PSScriptRoot -Parent
$nativeDir = Join-Path $root 'external\imagedecoder-houri\library\src\main\jniLibs\arm64-v8a'
$native = Join-Path $nativeDir 'libimagedecoder2.so'
if (!(Test-Path -LiteralPath $SourceApk -PathType Leaf)) { throw "Source APK missing: $SourceApk" }
$archive = [IO.Compression.ZipFile]::OpenRead($SourceApk)
try {
    $entry = $archive.GetEntry('lib/arm64-v8a/libimagedecoder2.so')
    if ($null -eq $entry -or $entry.Length -lt 1000000) { throw 'Source APK lacks the required ARM64 decoder library' }
    [IO.Directory]::CreateDirectory($nativeDir) | Out-Null
    $inputStream = $entry.Open()
    try {
        $outputStream = [IO.File]::Create($native)
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
} finally { $archive.Dispose() }
$sourceHash = (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash
Write-Output "Decoder source: $SourceApk"
Write-Output "Decoder SHA256: $sourceHash"
$env:JAVA_HOME = 'D:\VR Kommiku\tools\java\jdk-21.0.12.1+1'
$env:ANDROID_HOME = 'D:\VR Kommiku\tools\android-sdk'
$env:GODOT_BIN = 'D:\VR Kommiku\tools\godot\Godot_v4.6-stable_win64_console.exe'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$gradle = Join-Path $root 'gradlew.bat'
$options = @('--no-daemon', '--max-workers=1', '--no-parallel', '-Pkotlin.compiler.execution.strategy=in-process', '-Dorg.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=768m -Dfile.encoding=UTF-8', '-Pandroid.injected.build.abi=arm64-v8a', "-Pimagedecoder.prebuiltArm64=$native")
foreach ($task in @('spotlessApply', 'spotlessCheck', ':app:stageNomtlDebugQuestApk')) {
    & $gradle $task @options
    if ($LASTEXITCODE -ne 0) { throw "Gradle $task failed ($LASTEXITCODE)" }
}
$apk = Join-Path $root 'build\quest-raw\app-nomtl-arm64-v8a-debug.apk'
if (!(Test-Path -LiteralPath $apk)) { throw "Built ARM64 APK missing: $apk" }
$built = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $entry = $built.GetEntry('lib/arm64-v8a/libimagedecoder2.so')
    if ($null -eq $entry) { throw 'Built APK lacks the required ARM64 decoder library' }
    $stream = $entry.Open()
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
    if ($actual -ne $sourceHash) { throw "Built decoder SHA256 differs from source: $actual" }
    if ($null -eq $built.GetEntry('assets/vr.pck')) { throw 'Built APK lacks VR pack' }
} finally { $built.Dispose() }
Copy-Item -LiteralPath $apk -Destination $OutputApk -Force
Write-Output "Verified current APK: $OutputApk"
Write-Output "Decoder unchanged: $actual"
