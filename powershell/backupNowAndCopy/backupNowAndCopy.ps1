### usage: ./backupNowAndCopy.ps1 -vip mycluster -username myusername -domain mydomain.net -jobName 'My Job' -archiveTo 'My Target' -keepArchiveFor 5 -replicateTo mycluster2 -keepReplicaFor 5

### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip, # the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$username, # username (local or AD)
    [Parameter()][string]$domain = 'local', # local or AD domain
    [Parameter(Mandatory = $True)][string]$jobName, # job to run
    [Parameter()][string]$replicateTo = $null, # optional - remote cluster to replicate to
    [Parameter()][int]$keepReplicaFor = 5, # keep replica for x days
    [Parameter()][string]$archiveTo = $null, # optional - target to archive to
    [Parameter()][int]$keepArchiveFor = 5, # keep archive for x days
    [Parameter()][switch]$enable # enable a disabled job, run it, then disable when done
)

### source the cohesity-api helper code
. ./cohesity-api

### authenticate
apiauth -vip $vip -username $username -domain $domain

### find the jobID
$job = (api get protectionJobs | Where-Object name -ieq $jobName)
if($job){
    $jobID = $job.id

}else{
    Write-Warning "Job $jobName not found!"
    exit
}

$copyRunTargets = @()

if ($replicateTo) {
    $remote = api get remoteClusters | Where-Object {$_.name -eq $replicateTo}
    if ($remote) {
        $copyRunTargets = $copyRunTargets + @{
            "daysToKeep" = $keepReplicaFor;
            "replicationTarget" = @{
              "clusterId" = $remote.clusterId;
              "clusterName" = $remote.name
            };
            "type" = "kRemote"
          }
    }
    else {
        Write-Warning "Remote Cluster $replicateTo not found!"
        exit
    }
}

if($archiveTo){
    $vault = api get vaults | Where-Object {$_.name -eq $archiveTo}
    if($vault){
        $copyRunTargets = $copyRunTargets + @{
            "archivalTarget" = @{
              "vaultId" = $vault.id;
              "vaultName" = $vault.name;
              "vaultType" = "kCloud"
            };
            "daysToKeep" = $keepArchiveFor;
            "type" = "kArchival"
          }
    }else{
        Write-Warning "Archive target $archiveTo not found!"
        exit
    }
}

### RunProtectionJobParam object
$jobdata = @{
   "runType" = "kRegular"
   "copyRunTargets" = $copyRunTargets
}

### run protectionJob
"Running $jobName..."
if($enable){
    $enabled = api post protectionJobState/$jobID @{ 'pause' = $false }
}
$runJob = api post ('protectionJobs/run/' + $jobID) $jobdata
if($enable){
    sleep 2
    $disabled = api post protectionJobState/$jobID @{ 'pause' = $true }
}

