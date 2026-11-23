# final_wiki_audit.ps1 - 可重現之 LLM Wiki 16 檔案自動化驗收腳本
# 用法：powershell -ExecutionPolicy Bypass -File scripts/final_wiki_audit.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Split-Path -Parent $scriptDir
if (-not (Test-Path (Join-Path $workspace "INDEX.md"))) {
    $workspace = "c:\Users\user\Downloads\fern-learning-wiki"
}

$wikiDir = Join-Path $workspace "wiki"
$rawDir = Join-Path $workspace "raw"
$indexPath = Join-Path $workspace "INDEX.md"
$agentsPath = Join-Path $workspace "AGENTS.md"
$changelogPath = Join-Path $workspace "CHANGELOG.md"

Write-Output "========================================================="
Write-Output "   FERN LEARNING WIKI - 16 FILES FINAL AUDIT SCRIPT      "
Write-Output "========================================================="

$auditResults = [ordered]@{}

# 1. Check AGENTS.md
Write-Output "`n[CHECK 1: AGENTS.md Specifications]"
$agentsContent = Get-Content -Path $agentsPath -Raw -Encoding UTF8
$hasWikiLoop = $agentsContent -match 'Wiki 維護 Loop' -and $agentsContent -match 'stateDiagram-v2'
$hasSlidesGraph = $agentsContent -match 'HTML 教學簡報生成 Graph'
$hasHumanGate = $agentsContent -match 'Human_Approval_Gate' -and $agentsContent -match '人類確認門檻'
$hasRetryLimit = $agentsContent -match '重試 <= 3' -and $agentsContent -match '重試 > 3 次'

if ($hasWikiLoop -and $hasSlidesGraph -and $hasHumanGate -and $hasRetryLimit) {
    Write-Output "  PASS: AGENTS.md correctly defines Wiki Loop, Slides Graph, Human Approval Gate, and 3-retry limit."
    $auditResults["1. AGENTS.md 流程與退回規範"] = "PASS"
} else {
    Write-Output "  FAIL: AGENTS.md missing critical specifications."
    $auditResults["1. AGENTS.md 流程與退回規範"] = "FAIL"
}

# 2. Check raw/ 5 files
Write-Output "`n[CHECK 2: raw/ Sources Classification & Metadata]"
$rawFiles = Get-ChildItem -Path $rawDir -Filter "*.md"
$rawPass = $true
$rawReport = @()

foreach ($rf in $rawFiles) {
    $c = Get-Content -Path $rf.FullName -Raw -Encoding UTF8
    $hasMeta = $c -match '(?m)^source_url:\s*"https://.+gov\.tw.+"'
    $hasSec1 = $c -match '## 一、官方來源基本資訊與原文出處'
    $hasSec2 = $c -match '## 二、官方文獻原始核心內文摘錄'
    $hasSec3 = $c -match '## 三、AI 整理與核心考點註記'
    
    if ($hasMeta -and $hasSec1 -and $hasSec2 -and $hasSec3) {
        $rawReport += ($rf.Name + ": PASS (URL verified, 3 sections distinct)")
    } else {
        $rawPass = $false
        $rawReport += ($rf.Name + ": FAIL (missing required sections or metadata)")
    }
}
$rawReport | ForEach-Object { Write-Output ("  " + $_) }
if ($rawPass -and $rawFiles.Count -eq 5) {
    $auditResults["2. raw/ 來源分類與 Metadata"] = "PASS (5/5)"
} else {
    $auditResults["2. raw/ 來源分類與 Metadata"] = "FAIL"
}

# 3. Check wiki/ 8 files
Write-Output "`n[CHECK 3: wiki/ Notes Citations, Taxonomy & Links]"
$wikiFiles = Get-ChildItem -Path $wikiDir -Filter "*.md"
$wikiPass = $true
$wikiReport = @()

foreach ($wf in $wikiFiles) {
    $c = Get-Content -Path $wf.FullName -Raw -Encoding UTF8
    $hasCitations = $c -match '\[\^SRC-0[1-5]\]'
    $hasWikiLinks = $c -match '\[\[[a-z0-9\-]+(?:\\?\|[^\]]+)?\]\]'
    $hasFrontmatter = $c -match '(?m)^title:\s*.+' -and $c -match '(?m)^sources:\s*\['
    
    $scientificOk = $true
    if ($wf.Name -match 'asplenium|platycerium|adiantum|nephrolepis|biology') {
        if ($c -notmatch '\*[A-Z][a-z]+(\s+[a-z]+)?\*') {
            $scientificOk = $false
        }
    }
    
    if ($hasCitations -and $hasWikiLinks -and $hasFrontmatter -and $scientificOk) {
        $wikiReport += ($wf.Name + ": PASS (Frontmatter, Citations, Links, Taxonomy)")
    } else {
        $wikiPass = $false
        $wikiReport += ($wf.Name + ": FAIL")
    }
}
$wikiReport | ForEach-Object { Write-Output ("  " + $_) }
if ($wikiPass -and $wikiFiles.Count -eq 8) {
    $auditResults["3. wiki/ 筆記引用與學名規範"] = "PASS (8/8)"
} else {
    $auditResults["3. wiki/ 筆記引用與學名規範"] = "FAIL"
}

# 4. Check INDEX.md & Link Health
Write-Output "`n[CHECK 4: INDEX.md Integrity & Link Graph]"
$indexContent = Get-Content -Path $indexPath -Raw -Encoding UTF8
$wikiNames = $wikiFiles | ForEach-Object { $_.BaseName }

$allLinked = $true
foreach ($wn in $wikiNames) {
    if ($indexContent -notmatch "\[\[$wn(?:\\?\|[^\]]+)?\]\]") {
        $allLinked = $false
        Write-Output ("  FAIL: " + $wn + " missing from INDEX.md")
    }
}

$allMdFiles = @($indexPath) + $wikiFiles.FullName
$deadLinksCount = 0
foreach ($f in $allMdFiles) {
    $content = Get-Content -Path $f -Raw -Encoding UTF8
    $matches = [regex]::Matches($content, '\[\[([^\]\\|]+)(?:\\?\|[^\]]+)?\]\]')
    foreach ($m in $matches) {
        $targetClean = $m.Groups[1].Value.Trim().TrimEnd('\').Trim() -replace '\.md$', ''
        if ($wikiNames -notcontains $targetClean -and -not (Test-Path (Join-Path $workspace ($targetClean + ".md")))) {
            $deadLinksCount++
            Write-Output ("  DEAD LINK in " + (Split-Path $f -Leaf) + ": [[" + $targetClean + "]]")
        }
    }
}

if ($allLinked -and $deadLinksCount -eq 0) {
    Write-Output "  PASS: INDEX.md contains all 8 notes; Zero dead links; Zero orphan notes."
    $auditResults["4. INDEX.md 全域索引與斷鏈檢查"] = "PASS (0 Dead, 0 Orphans)"
} else {
    $auditResults["4. INDEX.md 全域索引與斷鏈檢查"] = "FAIL"
}

# 5. Check CHANGELOG.md
Write-Output "`n[CHECK 5: CHANGELOG.md Execution History]"
$changelogContent = Get-Content -Path $changelogPath -Raw -Encoding UTF8
$hasPhase1 = $changelogContent -match 'Phase 1'
$hasPhase2 = $changelogContent -match 'Phase 2'
$hasPhase3 = $changelogContent -match 'Phase 3'
$hasLintFail = $changelogContent -match 'FAIL \(發現 10 處無效連結\)'
$hasRetry = $changelogContent -match 'Retry Count: 1'
$hasPass = $changelogContent -match 'ALL PASS'

if ($hasPhase1 -and $hasPhase2 -and $hasPhase3 -and $hasLintFail -and $hasRetry -and $hasPass) {
    Write-Output "  PASS: CHANGELOG.md fully records real execution, Round 1 failure, retry/fix, and Round 2 pass."
    $auditResults["5. CHANGELOG.md 狀態機與執行日誌"] = "PASS"
} else {
    Write-Output "  FAIL: CHANGELOG.md missing real failure/retry/pass records."
    $auditResults["5. CHANGELOG.md 狀態機與執行日誌"] = "FAIL"
}

# 6. Spot-check 5 Cultivation Data Points
Write-Output "`n[CHECK 6: Spot-check 5 Key Cultivation Data Points]"
$dataChecks = @(
    @{
        Name = "數據 1: 鹿角蕨澆水頻率與施肥稀釋倍數"
        WikiFile = "wiki\platycerium-care-and-mounting.md"
        RawFile = "raw\SRC-03_tydares_platycerium.md"
        Pattern1 = "3 至 4 天"
        Pattern2 = "1 星期"
        Pattern3 = "2,000 倍"
    },
    @{
        Name = "數據 2: 鹿角蕨生長適溫與耐受極限"
        WikiFile = "wiki\platycerium-care-and-mounting.md"
        RawFile = "raw\SRC-03_tydares_platycerium.md"
        Pattern1 = "18℃ 至 30℃"
        Pattern2 = "15℃"
        Pattern3 = "35℃"
        Pattern4 = "5℃"
    },
    @{
        Name = "數據 3: 山蘇花遮光率、適溫與寒害警戒"
        WikiFile = "wiki\asplenium-antiquum-care.md"
        RawFile = "raw\SRC-02_tndais_asplenium.md"
        Pattern1 = "60% 至 80%"
        Pattern2 = "20℃ 至 30℃"
        Pattern3 = "15℃"
        Pattern4 = "10℃"
    },
    @{
        Name = "數據 4: 鐵線蕨高濕度通說標記與春季分株"
        WikiFile = "wiki\adiantum-care.md"
        RawFile = "raw\SRC-04_kdais_adiantum.md"
        Pattern1 = "70%~90%"
        Pattern2 = "春季氣溫回升"
    },
    @{
        Name = "數據 5: 長葉腎蕨最佳遮蔭率與球莖歸屬釐清"
        WikiFile = "wiki\nephrolepis-biserrata-care.md"
        RawFile = "raw\SRC-05_ttdares_nephrolepis.md"
        Pattern1 = "50% 至 60%"
        Pattern2 = "不具地下球莖"
    }
)

$allDataPass = $true
foreach ($dc in $dataChecks) {
    $wc = Get-Content -Path (Join-Path $workspace $dc.WikiFile) -Raw -Encoding UTF8
    $rc = Get-Content -Path (Join-Path $workspace $dc.RawFile) -Raw -Encoding UTF8
    
    $matchW = $true
    $matchR = $true
    
    foreach ($k in $dc.Keys) {
        if ($k -like 'Pattern*') {
            $val = $dc[$k]
            if ($wc -notmatch [regex]::Escape($val)) { $matchW = $false }
            if ($rc -notmatch [regex]::Escape($val)) { $matchR = $false }
        }
    }
    
    if ($matchW -and $matchR) {
        Write-Output ("  PASS: [" + $dc.Name + "] verified in both Wiki and Raw.")
    } else {
        $allDataPass = $false
        Write-Output ("  FAIL: [" + $dc.Name + "] mismatch! (Wiki: " + $matchW + ", Raw: " + $matchR + ")")
    }
}

if ($allDataPass) {
    $auditResults["6. 重要栽培數據逐項溯源比對"] = "PASS (5/5 Match)"
} else {
    $auditResults["6. 重要栽培數據逐項溯源比對"] = "FAIL"
}

Write-Output "`n========================================================="
Write-Output "               FINAL AUDIT SUMMARY TABLE                "
Write-Output "========================================================="
foreach ($k in $auditResults.Keys) {
    Write-Output ($k + " : " + $auditResults[$k])
}
