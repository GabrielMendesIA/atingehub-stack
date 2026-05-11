<#
.SYNOPSIS
  Sincroniza o repositório atingehub-stack a partir do ~/.claude/ pessoal do Gabriel.

.DESCRIPTION
  Copia skills, agentes e comandos do Claude Code local pro repo público,
  filtrando o que está em EXCLUDE.txt. Aborta se detectar segredos ou
  referências pessoais. Atualiza versão e CHANGELOG. Commita.

.PARAMETER Push
  Se setado, faz git push após o commit. Sem isso, só commita localmente.

.PARAMETER DryRun
  Não modifica arquivos finais nem commita — só mostra o que faria.

.PARAMETER BumpType
  Tipo de incremento de versão: patch (default), minor ou major.

.EXAMPLE
  pwsh ./scripts/sync-from-local.ps1
  Roda o sync completo, commita local, não dá push.

.EXAMPLE
  pwsh ./scripts/sync-from-local.ps1 -Push
  Sincroniza e dá push pro GitHub.

.EXAMPLE
  pwsh ./scripts/sync-from-local.ps1 -DryRun
  Mostra o que faria sem mexer em nada.
#>
[CmdletBinding()]
param(
  [switch]$Push,
  [switch]$DryRun,
  [ValidateSet('patch', 'minor', 'major')]
  [string]$BumpType = 'patch'
)

$ErrorActionPreference = 'Stop'

# === Paths ===
$RepoRoot       = Split-Path -Parent $PSScriptRoot
$ClaudeHome     = Join-Path $env:USERPROFILE '.claude'
$SkillsSource   = Join-Path $ClaudeHome 'skills'
$AgentsSource   = Join-Path $ClaudeHome 'agents'
$CommandsSource = Join-Path $ClaudeHome 'commands'
$SkillsDest     = Join-Path $RepoRoot 'skills'
$AgentsDest     = Join-Path $RepoRoot 'agents'
$CommandsDest   = Join-Path $RepoRoot 'commands'
$ExcludeFile    = Join-Path $PSScriptRoot 'EXCLUDE.txt'
$PluginJson     = Join-Path $RepoRoot '.claude-plugin\plugin.json'
$MarketplaceJson= Join-Path $RepoRoot '.claude-plugin\marketplace.json'
$Changelog      = Join-Path $RepoRoot 'CHANGELOG.md'

function Write-FileNoBom {
  param([string]$Path, [string]$Content)
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Section {
  param([string]$Title)
  Write-Host ""
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

# === [0] Pré-flight ===
Section "Pre-flight checks"
foreach ($path in @($SkillsSource, $RepoRoot, $ExcludeFile, $PluginJson)) {
  if (-not (Test-Path $path)) {
    Write-Host "ERRO: caminho nao encontrado: $path" -ForegroundColor Red
    exit 1
  }
}
Write-Host "OK"

# === [1] Carregar lista de exclusão ===
Section "Carregando EXCLUDE.txt"
$excludeList = @()
Get-Content $ExcludeFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -and -not $line.StartsWith('#')) {
    $excludeList += $line
  }
}
Write-Host "Bloqueadas: $($excludeList.Count) entradas"
$excludeList | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }

# === [2] Limpar destino ===
Section "Limpando pastas destino"
foreach ($dest in @($SkillsDest, $AgentsDest, $CommandsDest)) {
  if (Test-Path $dest) {
    if (-not $DryRun) {
      Get-ChildItem -Path $dest -Force | Remove-Item -Recurse -Force
    }
    Write-Host "Limpo: $dest"
  } else {
    if (-not $DryRun) {
      New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    Write-Host "Criado: $dest"
  }
}

# === [3] Copiar skills ===
Section "Copiando skills"
$skillsCopied = 0
$skillsSkipped = 0
$skillNames = @()
Get-ChildItem -Path $SkillsSource -Directory | ForEach-Object {
  if ($excludeList -contains $_.Name) {
    Write-Host "  [SKIP] $($_.Name)" -ForegroundColor DarkGray
    $skillsSkipped++
  } else {
    if (-not $DryRun) {
      Copy-Item -Path $_.FullName -Destination $SkillsDest -Recurse -Force
    }
    Write-Host "  [OK]   $($_.Name)" -ForegroundColor DarkGreen
    $skillsCopied++
    $skillNames += $_.Name
  }
}
Write-Host ""
Write-Host "Total: $skillsCopied copiadas, $skillsSkipped bloqueadas"

# === [4] Copiar agentes (com sanitização) ===
Section "Copiando agentes (sanitizados)"
$agentsCopied = 0
if (Test-Path $AgentsSource) {
  Get-ChildItem -Path $AgentsSource -File -Filter '*.md' | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    $original = $content
    # Despersonalizar refs a projetos pessoais
    $content = $content -replace '\bacaialgomais\b', 'seu-projeto'
    $content = $content -replace '\balgomais\b', 'seu-projeto'
    $content = $content -replace '\bdespachai\b', 'seu-projeto'
    $content = $content -replace '\bimunid\b', 'seu-projeto'
    $content = $content -replace '\bia-para-negocios\b', 'seu-projeto'
    $content = $content -replace '\brenegocia\b', 'seu-projeto'
    # Ordem importa: substituir nome completo antes do primeiro nome.
    $content = $content -replace 'Gabriel Mendes', 'o consultor'
    $content = $content -replace '\bGabriel\b', 'o usuário'
    $content = $content -replace 'c--Users-mende', '<seu-usuário>'
    $changed = ($content -ne $original)
    $destFile = Join-Path $AgentsDest $_.Name
    if (-not $DryRun) {
      Write-FileNoBom -Path $destFile -Content $content
    }
    $tag = if ($changed) { "[SANIT]" } else { "[OK]   " }
    Write-Host "  $tag $($_.Name)" -ForegroundColor DarkGreen
    $agentsCopied++
  }
}
Write-Host "Total: $agentsCopied agentes"

# === [5] Copiar comandos ===
Section "Copiando slash commands"
$commandsCopied = 0
if (Test-Path $CommandsSource) {
  Get-ChildItem -Path $CommandsSource -File -Filter '*.md' | ForEach-Object {
    if (-not $DryRun) {
      Copy-Item -Path $_.FullName -Destination $CommandsDest -Force
    }
    Write-Host "  [OK] $($_.Name)" -ForegroundColor DarkGreen
    $commandsCopied++
  }
}
Write-Host "Total: $commandsCopied comandos"

# === [6] Auditoria de segurança ===
Section "Auditoria de segurança"
# Patterns que ABORTAM o sync se forem encontrados
$abortPatterns = @(
  @{ Pattern = 'BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY'; Name = 'private key block' },
  @{ Pattern = 'sk_live_[A-Za-z0-9]{20,}'; Name = 'Stripe live key' },
  @{ Pattern = 'AKIA[0-9A-Z]{16}'; Name = 'AWS access key' },
  @{ Pattern = 'ghp_[A-Za-z0-9]{30,}'; Name = 'GitHub personal token' },
  @{ Pattern = 'xox[baprs]-[A-Za-z0-9-]{10,}'; Name = 'Slack token' },
  @{ Pattern = 'mendesofc1@gmail\.com'; Name = 'email pessoal Gabriel' },
  @{ Pattern = 'C:\\\\Users\\\\mende'; Name = 'caminho pessoal Windows' }
)
$violations = @()
$searchPaths = @($SkillsDest, $AgentsDest, $CommandsDest)
foreach ($p in $searchPaths) {
  if (-not (Test-Path $p)) { continue }
  Get-ChildItem -Path $p -Recurse -File | ForEach-Object {
    $f = $_
    try {
      $text = Get-Content $f.FullName -Raw -ErrorAction Stop
      foreach ($pat in $abortPatterns) {
        if ($text -match $pat.Pattern) {
          $rel = $f.FullName.Substring($RepoRoot.Length + 1)
          $violations += "  $rel :: $($pat.Name)"
        }
      }
    } catch {
      # binário ou inacessível — pular
    }
  }
}
if ($violations.Count -gt 0) {
  Write-Host ""
  Write-Host "ABORT: detectados $($violations.Count) possiveis vazamentos:" -ForegroundColor Red
  $violations | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  Write-Host ""
  Write-Host "Edite os arquivos ofensivos ou adicione a skill em EXCLUDE.txt e rode de novo." -ForegroundColor Yellow
  exit 1
}
Write-Host "OK — nenhum padrao sensivel encontrado."

# === [7] Bump de versão ===
Section "Atualizando versão"
$plugin = Get-Content $PluginJson -Raw | ConvertFrom-Json
$oldVersion = $plugin.version
$parts = @($oldVersion -split '\.')
switch ($BumpType) {
  'patch' { $parts[2] = [string]([int]$parts[2] + 1) }
  'minor' { $parts[1] = [string]([int]$parts[1] + 1); $parts[2] = '0' }
  'major' { $parts[0] = [string]([int]$parts[0] + 1); $parts[1] = '0'; $parts[2] = '0' }
}
$newVersion = $parts -join '.'

if (-not $DryRun) {
  $plugin.version = $newVersion
  $pluginJsonText = ($plugin | ConvertTo-Json -Depth 10)
  Write-FileNoBom -Path $PluginJson -Content $pluginJsonText

  $mp = Get-Content $MarketplaceJson -Raw | ConvertFrom-Json
  $mp.plugins[0].version = $newVersion
  $mpJsonText = ($mp | ConvertTo-Json -Depth 10)
  Write-FileNoBom -Path $MarketplaceJson -Content $mpJsonText
}
Write-Host "Versao: $oldVersion -> $newVersion ($BumpType)"

# === [8] Atualizar CHANGELOG ===
Section "Atualizando CHANGELOG"
$date = Get-Date -Format 'yyyy-MM-dd'
$entry = @"
## [$newVersion] - $date

### Sincronizado
- $skillsCopied skills copiadas, $skillsSkipped bloqueadas via EXCLUDE.txt
- $agentsCopied agentes, $commandsCopied slash commands

"@

if (-not $DryRun) {
  $changelogContent = Get-Content $Changelog -Raw
  $idx = $changelogContent.IndexOf("`n## ")
  if ($idx -gt 0) {
    $header = $changelogContent.Substring(0, $idx + 1)
    $rest = $changelogContent.Substring($idx + 1)
    $newContent = $header + $entry + "`n" + $rest
    Write-FileNoBom -Path $Changelog -Content $newContent
  } else {
    Write-FileNoBom -Path $Changelog -Content ($changelogContent + "`n" + $entry)
  }
}
Write-Host "Entry adicionado: v$newVersion"

# === [9] Git commit + push opcional ===
Section "Git"
if ($DryRun) {
  Write-Host "DryRun ativo — nenhum git operation." -ForegroundColor Yellow
} else {
  Push-Location $RepoRoot
  try {
    & git add -A
    $status = & git status --porcelain
    if ($status) {
      & git commit -m "sync v$newVersion ($skillsCopied skills, $agentsCopied agents, $commandsCopied commands)"
      Write-Host "Commit criado."
      if ($Push) {
        & git push
        Write-Host "Push concluido."
      } else {
        Write-Host "Sem push (use -Push pra subir pro remoto)." -ForegroundColor Yellow
      }
    } else {
      Write-Host "Sem mudancas — nada pra commitar."
    }
  } finally {
    Pop-Location
  }
}

Section "Resumo"
Write-Host "Skills: $skillsCopied copiadas / $skillsSkipped bloqueadas"
Write-Host "Agentes: $agentsCopied"
Write-Host "Comandos: $commandsCopied"
Write-Host "Versao: $newVersion"
Write-Host ""
Write-Host "Sync concluido." -ForegroundColor Green
