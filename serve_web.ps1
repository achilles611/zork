param(
    [int]$Port = 8000,
    [switch]$Https
)

$root = Join-Path $PSScriptRoot "build\web"

if (-not (Test-Path $root)) {
    Write-Error "Web build not found at $root"
    exit 1
}

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

function Get-IPv4Addresses {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -ne "127.0.0.1" -and
            $_.IPAddress -notlike "169.254.*"
        } |
        Select-Object -ExpandProperty IPAddress -Unique
}

function Resolve-RequestedFile {
    param([string]$RequestPath)

    $requested = $RequestPath.TrimStart("/")
    if ([string]::IsNullOrEmpty($requested)) {
        $requested = "index.html"
    }

    $relative = $requested -replace "/", "\"
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
    $root_full = [System.IO.Path]::GetFullPath($root)

    if (-not $resolved.StartsWith($root_full, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if (-not (Test-Path $resolved -PathType Leaf)) {
        return $null
    }

    return $resolved
}

function Get-ContentType {
    param([string]$FilePath)

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $content_type = $mime_types[$extension]
    if ([string]::IsNullOrEmpty($content_type)) {
        return "application/octet-stream"
    }

    return $content_type
}

function Send-StreamResponse {
    param(
        [Parameter(Mandatory = $true)] $Stream,
        [int]$StatusCode,
        [string]$ReasonPhrase,
        [string]$ContentType,
        [byte[]]$Body,
        [long]$ContentLength
    )

    $writer = [System.IO.StreamWriter]::new($Stream, [System.Text.Encoding]::ASCII, 1024, $true)
    $writer.NewLine = "`r`n"
    $writer.WriteLine("HTTP/1.1 $StatusCode $ReasonPhrase")
    $writer.WriteLine("Content-Length: $ContentLength")
    $writer.WriteLine("Content-Type: $ContentType")
    $writer.WriteLine("Connection: close")
    $writer.WriteLine("")
    $writer.Flush()

    if ($Body -ne $null -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
        $Stream.Flush()
    }
}

function Handle-Request {
    param(
        [Parameter(Mandatory = $true)] $Stream,
        [string]$Method,
        [string]$Target
    )

    if ($Method -notin @("GET", "HEAD")) {
        $body = [System.Text.Encoding]::UTF8.GetBytes("Method not allowed")
        Send-StreamResponse -Stream $Stream -StatusCode 405 -ReasonPhrase "Method Not Allowed" -ContentType "text/plain; charset=utf-8" -Body $body -ContentLength $body.Length
        return
    }

    $path_only = $Target.Split("?")[0]
    $decoded_path = [System.Uri]::UnescapeDataString($path_only)
    $file_path = Resolve-RequestedFile -RequestPath $decoded_path

    if ($null -eq $file_path) {
        $body = [System.Text.Encoding]::UTF8.GetBytes("Not found")
        Send-StreamResponse -Stream $Stream -StatusCode 404 -ReasonPhrase "Not Found" -ContentType "text/plain; charset=utf-8" -Body $body -ContentLength $body.Length
        return
    }

    $file_info = Get-Item $file_path
    $content_type = Get-ContentType -FilePath $file_path
    if ($Method -eq "HEAD") {
        Send-StreamResponse -Stream $Stream -StatusCode 200 -ReasonPhrase "OK" -ContentType $content_type -Body $null -ContentLength $file_info.Length
        return
    }

    $buffer = [System.IO.File]::ReadAllBytes($file_path)
    Send-StreamResponse -Stream $Stream -StatusCode 200 -ReasonPhrase "OK" -ContentType $content_type -Body $buffer -ContentLength $buffer.Length
}

$ipv4_addresses = Get-IPv4Addresses

if (-not $Https) {
    $listener = [System.Net.HttpListener]::new()
    $prefixes = [System.Collections.Generic.List[string]]::new()
    $prefixes.Add("http://localhost:$Port/")
    $prefixes.Add("http://127.0.0.1:$Port/")

    foreach ($ip in $ipv4_addresses) {
        $prefixes.Add("http://${ip}:$Port/")
    }

    foreach ($prefix in $prefixes) {
        $listener.Prefixes.Add($prefix)
    }

    $listener.Start()

    Write-Host "Serving $root on:"
    foreach ($prefix in $prefixes) {
        Write-Host "  $prefix"
    }
    Write-Host "Press Ctrl+C to stop."

    try {
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request_path = $context.Request.Url.AbsolutePath.TrimStart("/")
            $file_path = Resolve-RequestedFile -RequestPath $request_path

            if ($null -eq $file_path) {
                $context.Response.StatusCode = 404
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not found")
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.Close()
                continue
            }

            $context.Response.ContentType = Get-ContentType -FilePath $file_path
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

    exit 0
}

$pfx_path = Join-Path $PSScriptRoot "zork-local-https.pfx"
$password_path = Join-Path $PSScriptRoot "zork-local-https.password.txt"

if (-not (Test-Path $pfx_path) -or -not (Test-Path $password_path)) {
    Write-Error "HTTPS certificate files are missing. Run setup_https_dev.ps1 first."
    exit 1
}

$plain_password = (Get-Content $password_path -Raw).Trim()
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $pfx_path,
    $plain_password,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet
)

if (-not $cert.HasPrivateKey) {
    Write-Error "HTTPS certificate loaded without a private key. Run setup_https_dev.ps1 again."
    exit 1
}

$tcp_listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$tcp_listener.Start()

Write-Host "Serving $root on:"
Write-Host "  https://localhost:$Port/"
foreach ($ip in $ipv4_addresses) {
    Write-Host "  https://${ip}:$Port/"
}
Write-Host "Press Ctrl+C to stop."

try {
    while ($true) {
        $client = $tcp_listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $ssl_stream = [System.Net.Security.SslStream]::new($stream, $false)
            try {
                $ssl_stream.AuthenticateAsServer(
                    $cert,
                    $false,
                    [System.Security.Authentication.SslProtocols]::Tls12,
                    $false
                )
            } catch {
                Write-Warning "TLS handshake failed: $($_.Exception.Message)"
                continue
            }

            $reader = [System.IO.StreamReader]::new($ssl_stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
            $request_line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($request_line)) {
                continue
            }

            while ($true) {
                $header_line = $reader.ReadLine()
                if ($null -eq $header_line -or $header_line.Length -eq 0) {
                    break
                }
            }

            $parts = $request_line.Split(" ")
            if ($parts.Length -lt 2) {
                $body = [System.Text.Encoding]::UTF8.GetBytes("Bad request")
                Send-StreamResponse -Stream $ssl_stream -StatusCode 400 -ReasonPhrase "Bad Request" -ContentType "text/plain; charset=utf-8" -Body $body -ContentLength $body.Length
                continue
            }

            Handle-Request -Stream $ssl_stream -Method $parts[0].ToUpperInvariant() -Target $parts[1]
        }
        finally {
            if ($ssl_stream) {
                $ssl_stream.Dispose()
            }
            if ($client) {
                $client.Dispose()
            }
        }
    }
}
finally {
    $tcp_listener.Stop()
}
