param(
 [Parameter(Mandatory=$true)][ValidateSet('on','off','status','zero')][string]$Action,
 [switch]$ConfirmZero,
 [string]$Port='COM15'
)
$ErrorActionPreference='Stop'
$motorSerial=New-Object System.IO.Ports.SerialPort $Port,115200,'None',8,'One'
$motorSerial.DtrEnable=$false;$motorSerial.RtsEnable=$false;$motorSerial.Handshake='None'
$motorStarted=$false;$motorConfirmed=$false
function Read-MotorState([string]$Command, [int]$TimeoutMs=3000) {
 # Retry read-only queries only. Never replay zero/start on a lost reply.
 $motorAttempts=1
 if($Command -eq '?'){$motorAttempts=3}
 $motorReply='';$motorSerial.DiscardInBuffer()
 for($motorAttempt=1;$motorAttempt -le $motorAttempts;$motorAttempt++){
 $motorSerial.Write($Command)
 $motorDeadline=(Get-Date).AddMilliseconds($TimeoutMs)
 while((Get-Date) -lt $motorDeadline){
  $motorReply+=$motorSerial.ReadExisting()
  $motorMatch=[regex]::Match($motorReply,'(?m)^STEPPER v([0-9]+) ([^\r\n]*)[\r\n]')
  if($motorMatch.Success){
   $motorState=@{version=[int]$motorMatch.Groups[1].Value}
   foreach($field in [regex]::Matches($motorMatch.Groups[2].Value,'(\w+)=(-?\d+)')){
    $motorState[$field.Groups[1].Value]=[long]$field.Groups[2].Value
   }
   foreach($name in @('available','mode','status','pos')){if(!$motorState.ContainsKey($name)){throw "Missing state field $name"}}
   Write-Host $motorMatch.Value.Trim()
   return $motorState
  }
  Start-Sleep -Milliseconds 30
 }
 }
 throw "No stepper status reply on $Port after $motorAttempts attempt(s). Check board startup, firmware and serial-port owner."
}
try {
 $motorSerial.Open()
 # Allow the USB UART to settle; DTR/RTS remain disabled (no board reset).
 Start-Sleep -Milliseconds 150
 if($Action -eq 'off'){
  $state=Read-MotorState 's'
  if($state.mode -eq 0 -and ($state.status -band 8)){
   Start-Sleep -Milliseconds 100;$state=Read-MotorState '?'
  }
  if($state.mode -ne 0 -or ($state.status -band 13)){throw 'OFF not confirmed'}
  Write-Host 'OFF confirmed.'
 } else {
  $state=Read-MotorState '?'
  if($Action -ne 'status'){
   if($state.version -notin @(82,83)){throw 'Expected v82/v83. Restart after programming; no motion command sent.'}
   if($state.available -ne 1){throw 'Stepper hardware unavailable'}
   if($Action -eq 'on' -and $state.mode -eq 2){
    if(($state.status -band 7) -ne 3){throw 'Controller fault'}
    Write-Host 'Already ON.'
   } else {
    if($state.mode -ne 0 -or ($state.status -band 13)){throw 'Controller not safely OFF'}
    if($ConfirmZero){
     # Explicit operator assertion: current physical pose is safe as reference.
     $state=Read-MotorState 'z'
     if(($state.status -band 7) -ne 2 -or $state.pos -ne 0){throw 'Zero rejected'}
    }
    if($Action -eq 'zero'){
     if(!$ConfirmZero){throw 'Use zero -ConfirmZero only at a safe reference pose.'}
     Write-Host 'Reference zero confirmed; motors remain OFF.'
    } else {
     if(!($state.status -band 2)){throw 'No origin. At a safe middle pose use on -ConfirmZero.'}
     $motorStarted=$true;$state=Read-MotorState 'g'
     if($state.mode -ne 2 -or ($state.status -band 7) -ne 3){throw 'ON not confirmed'}
     $motorConfirmed=$true;Write-Host 'ON: persistent tracking; no target means waiting.'
    }
   }
  }
 }
} finally {
 if($motorSerial.IsOpen){
  if($motorStarted -and !$motorConfirmed){$motorSerial.Write('s');Start-Sleep -Milliseconds 100}
  $motorSerial.Close()
 }
 $motorSerial.Dispose()
}
