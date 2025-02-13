# VHDX image is available for download from the alpha version 3941.0.0
curl.exe --progress-bar -LO "https://alpha.release.flatcar-linux.net/amd64-usr/3941.0.0/flatcar_production_hyperv_vhdx_image.vhdx.zip"
Expand-Archive flatcar_production_hyperv_vhdx_image.vhdx.zip .

#Deploying a new virtual machine on Hyper-V using Ignition with autologin and TPM LUKS2 root partition encryption 

$vmName = "my_flatcar_01"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$vmDisk = "$scriptPath\flatcar_production_hyperv_vhdx_image.vhdx"


New-VM -Name $vmName -MemoryStartupBytes 2GB `
    -BootDevice VHD -SwitchName (Get-VMSwitch | Where-Object {$_.SwitchType -eq "External"} | Select-Object -First 1 -ExpandProperty Name) `
    -VHDPath $vmDisk -Generation 2

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
  files:
    - path: /etc/systemd/network/00-static.network
      filesystem: root
      mode: 0644
      contents:
        inline: |
          [Match]
          Name=eth0

          [Network]
          Address=192.168.42.147/24
          Gateway=192.168.42.253
          DNS=1.1.1.1 8.8.8.8
systemd:
  units:
    - name: systemd-networkd.service
      enabled: true
      contents: |
        [Unit]
        Description=Network Service
        Wants=network.target
        Before=network.target
        [Service]
        ExecStart=/lib/systemd/systemd-networkd
        Restart=always
        [Install]
        WantedBy=multi-user.target
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
