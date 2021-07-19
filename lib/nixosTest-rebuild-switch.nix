# NixOS configuration that allows a nixosTest virtual machine to "nixos-rebuild switch".
# You'll also need to include the config's system.build.toplevel in system.extraDependencies.

{ lib, pkgs, modulesPath, ... }: {
  imports = [
    (modulesPath + "/installer/cd-dvd/channel.nix")
    (modulesPath + "/profiles/base.nix")
    (modulesPath + "/testing/test-instrumentation.nix")
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  nix.binaryCaches = lib.mkOverride 90 [ ];
  nix.binaryCachePublicKeys = lib.mkOverride 90 [ ];
  nix.extraOptions = ''
    hashed-mirrors =
    connect-timeout = 1
  '';

  system.extraDependencies = with pkgs; [
    # List of packages from installer test
    curl # To diagnose fetch requests
    desktop-file-utils
    docbook5
    docbook_xsl_ns
    grub
    libxml2.bin
    libxslt.bin
    nixos-artwork.wallpapers.simple-dark-gray-bottom
    ntp
    perlPackages.ListCompare
    perlPackages.XMLLibXML
    shared-mime-info
    stdenvNoCC
    sudo
    texinfo
    unionfs-fuse
    xorg.lndir
  ];

  # Don't try to install bootloaders in a VM
  boot.loader.grub.devices = lib.mkForce [ "nodev" ];
}
