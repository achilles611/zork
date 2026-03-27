param(
    [int]$Port = 8000
)

$root = Join-Path $PSScriptRoot "build\web"

if (-not (Test-Path $root)) {
    Write-Error "Web build not found at $root"
    exit 1
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "Serving $root at http://localhost:$Port/"
Write-Host "Press Ctrl+C to stop."

$mime_types = @{
    ".html" = "text/html; charset=utf-8"
    ".js" = "application/javascript; charset=utf-8"
    ".wasm" = "application/wasm"
    ".pck" = "application/octet-stream"
    ".png" = "image/png"
    ".json" = "application/json; charset=utf-8"
    ".svg" = "image/svg+xml"
    ".css" = "text/css; charset=utf-8"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request_path = $context.Request.Url.AbsolutePath.TrimStart("/")
        if ([string]::IsNullOrEmpty($request_path)) {
            $request_path = "index.html"
        }

        $safe_path = $request_path -replace "/", "\"
        $file_path = Join-Path $root $safe_path

        if (-not $file_path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $file_path -PathType Leaf)) {
            $context.Response.StatusCode = 404
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not found")
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $context.Response.Close()
            continue
        }

        $extension = [System.IO.Path]::GetExtension($file_path).ToLowerInvariant()
        $context.Response.ContentType = $mime_types[$extension]
        if ([string]::IsNullOrEmpty($context.Response.ContentType)) {
            $context.Response.ContentType = "application/octet-stream"
        }

        $buffer = [System.IO.File]::ReadAllBytes($file_path)
        $context.Response.ContentLength64 = $buffer.Length
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $context.Response.Close()
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
