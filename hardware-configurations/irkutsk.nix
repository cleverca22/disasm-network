# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, ... }:

{
  imports =
    [ <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "rtsx_pci_sdmmc" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "zpool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/nix" = { device = "zpool/nix";
      fsType = "zfs";
    };
  fileSystems."/var/lib/docker" = { device = "zpool/docker";
      fsType = "zfs";
    };
  fileSystems."/var/lib/containers" = { device = "zpool/containers";
      fsType = "zfs";
    };
  fileSystems."/home" =
    { device = "zpool/home";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/C643-53CB";
      fsType = "vfat";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/8d25271a-26e2-4aed-9e7a-a8909fccf8f2"; }
    ];

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
