# VHDX image is available for download from the alpha version 3941.0.0
curl.exe --progress-bar -LO "https://alpha.release.flatcar-linux.net/amd64-usr/3941.0.0/flatcar_production_hyperv_vhdx_image.vhdx.zip"
Expand-Archive flatcar_production_hyperv_vhdx_image.vhdx.zip .

#Deploying a new virtual machine on Hyper-V using Ignition with autologin and TPM LUKS2 root partition encryption 

$vmName = "my_flatcar_01"
$vmDisk = "flatcar_production_hyperv_vhdx_image.vhdx"

New-VM -Name $vmName -MemoryStartupBytes 2GB `
    -BootDevice VHD -SwitchName "VMSwitch" -VHDPath $vmDisk -Generation 2
Set-VMFirmware -EnableSecureBoot "Off" -VMName $vmName

# The core user password is set to foo

$ignitionMetadata = @'
variant: flatcar
version: 1.0.0
kernel_arguments:
  should_exist:
    - flatcar.autologin
passwd:
  users:
    - name: core
      password_hash: HXzKuaMEHskfU
storage:
  luks:
  - name: rootencrypted
    wipe_volume: true
    device: "/dev/disk/by-partlabel/ROOT"
  filesystems:
    - device: /dev/mapper/rootencrypted
      format: ext4
      label: ROOT
systemd:
  units:
    - name: cryptenroll-helper.service
      enabled: true
      contents: |
        [Unit]
        ConditionFirstBoot=true
        OnFailure=emergency.target
        OnFailureJobMode=isolate
        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=systemd-cryptenroll --tpm2-device=auto --unlock-key-file=/etc/luks/rootencrypted --wipe-slot=0 --tpm2-pcrs= /dev/disk/by-partlabel/ROOT
        ExecStart=rm /etc/luks/rootencrypted
        [Install]
        WantedBy=multi-user.target
'@
echo $ignitionMetadata > ignition.yaml

# download the butane binary to create the raw ignition metadata
# https://github.com/coreos/butane/releases
curl.exe -sLO "https://github.com/coreos/butane/releases/download/v0.20.0/butane-x86_64-pc-windows-gnu.exe"

# transform the Ignition metadata from Butane format to Ignition raw
.\butane-x86_64-pc-windows-gnu.exe ".\ignition.yaml" -o ".\ignition.json"

# download the tool kvpctl to set the Ignition metadata from
# https://github.com/containers/libhvee/releases
# See: https://docs.fedoraproject.org/en-US/fedora-coreos/provisioning-hyperv/
curl.exe -sLO "https://github.com/containers/libhvee/releases/download/v0.7.1/kvpctl-amd64.exe.zip"
Expand-Archive kvpctl-amd64.exe.zip . -Force
.\kvpctl-amd64.exe "$vmName" add-ign ignition.json

Set-VMKeyProtector -VMName $vmName -NewLocalKeyProtector
Enable-VMTPM -VMName $vmName

Start-VM -Name $vmName

# Wait a few seconds to allow the VM to start and obtain an IP address
Start-Sleep -Seconds 95

# Retrieve the VM's IP address
$vmIp = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses

# Display the IP address
if ($vmIp) {
    Write-Host "The IP address of the virtual machine '$vmName' is: $vmIp"
} else {
    Write-Host "Unable to retrieve the VM's IP address. Make sure the VM is properly connected to the network."
}