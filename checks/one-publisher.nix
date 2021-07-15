{ lib, gnused, nixos, nixosTest, trustix, trustixSrc, writeShellScript
, writeText, }:
let
  inherit (lib) filterAttrs hasPrefix mapAttrsToList optional;

  trustixModule = trustixSrc + "/nixos";

  trustixKeyConfig = writeText "trustixKeyConfig" ''
    { pkgs, ... }: {
      config = {
        system.activationScripts.trustix-create-key = '''
          if [[ ! -e /keys/trustix-priv ]];then
            mkdir -p /keys
            ''${pkgs.trustix}/bin/trustix generate-key --privkey /keys/trustix-priv --pubkey /keys/trustix-pub
          fi
        ''';
      };
    }
  '';

  publisherConfig = writeText "publisherConfig" ''
    {
      services.trustix = {
        enable = true;
        signers.aisha-snakeoil = {
          type = "ed25519";
          ed25519 = { private-key-path = "/keys/trustix-priv"; };
        };
        publishers = [{
          signer = "aisha-snakeoil";
          protocol = "nix";
          publicKey = {
            type = "ed25519";
            pub = "@pubkey@";
          };
        }];
      };
    }
  '';

  mkConfig = writeShellScript "mkConfig" ''
    set -euxo pipefail
    mkdir -p /etc/nixos
    ${gnused}/bin/sed "s,@pubkey@,$(< /keys/trustix-pub)," ${publisherConfig} > /etc/nixos/publisher.nix
    cat > /etc/nixos/configuration.nix <<EOF
    {
      imports = [
        ${../lib/nixosTest-rebuild-switch.nix}
        ${trustixModule}
        ${trustixKeyConfig}
        ./publisher.nix
      ];
    }
    EOF
  '';

in nixosTest {
  name = "one-publisher";
  nodes = {
    alisha = { pkgs, ... }: {
      imports = [
        ../lib/nixosTest-rebuild-switch.nix
        trustixModule
        "${trustixKeyConfig}"
      ];
      system.extraDependencies = [
        pkgs.hello.inputDerivation
        pkgs.remarshal # For building trustix-config.toml
        (nixos {
          imports = [
            ../lib/nixosTest-rebuild-switch.nix
            trustixModule
            "${trustixKeyConfig}"
            "${publisherConfig}"
          ];
        }).toplevel
      ];
      virtualisation.diskSize = "1000";
      virtualisation.memorySize = "1G";
    };
  };
  testScript = ''
    alisha.wait_for_file("/keys/trustix-pub")
    alisha.succeed(
        "${mkConfig}",
        "nixos-rebuild switch --show-trace",
    )
    alisha.succeed("nix-build '<nixpkgs>' -A hello")
  '';
}
