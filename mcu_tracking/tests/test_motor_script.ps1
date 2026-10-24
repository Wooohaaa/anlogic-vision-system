$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '../motor.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $source),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'motor.ps1 parse failed'}
$fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-MotorState'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$Port='MOCK'
function New-Mock([int]$ReplyAt,[string[]]$Chunks){
 $mock=[pscustomobject]@{Writes=[System.Collections.Generic.List[string]]::new();ReplyAt=$ReplyAt;Chunks=$Chunks;Index=0;Discards=0}
 $mock | Add-Member ScriptMethod DiscardInBuffer {$this.Discards++}
 $mock | Add-Member ScriptMethod Write {param($s) $this.Writes.Add($s)}
 $mock | Add-Member ScriptMethod ReadExisting {
  if($this.Writes.Count -ge $this.ReplyAt -and $this.Index -lt $this.Chunks.Count){$s=$this.Chunks[$this.Index];$this.Index++;return $s}
  return ''
 }
 return $mock
}
$line="STEPPER v82 available=1 mode=0 status=0 pos=-2`r`n"
$motorSerial=New-Mock 2 @($line)
$state=Read-MotorState '?' 40
if($state.version -ne 82 -or $state.pos -ne -2 -or $motorSerial.Writes.Count -ne 2){throw 'Read-only retry failed'}
$motorSerial=New-Mock 1 @("ARUCO ready`r`nSTE",'PPER v82 available=1 mode=0 status=0 pos=0',"`r`n")
$state=Read-MotorState '?' 150
if($state.mode -ne 0 -or $motorSerial.Writes.Count -ne 1){throw 'Fragmented reply failed'}
foreach($command in @('z','g','s','?')){
 $motorSerial=New-Mock 99 @($line)
 $failed=$false
 try {$null=Read-MotorState $command 1} catch {$failed=$true}
 $expected=1;if($command -eq '?'){$expected=3}
 if(!$failed -or $motorSerial.Writes.Count -ne $expected){throw "Unsafe retry behavior: $command"}
}
Write-Host 'PASS: read-only retries, fragmented CRLF, bounded timeout, no command replay.'
