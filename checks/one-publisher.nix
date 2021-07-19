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

  binaryCacheKeyConfig = writeText "binaryCacheKeyConfig" ''
    { pkgs, ... }: {
      config = {
        system.activationScripts.trustix-create-key = '''
          if [[ ! -e /keys/cache-priv-key.pem ]];then
            mkdir -p /keys
            ''${pkgs.nix}/bin/nix-store --generate-binary-cache-key clint /keys/cache-priv-key.pem /keys/cache-pub-key.pem
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
            pub = "@trustixPubKey@";
          };
        }];
      };
    }
  '';

  log-local-builds = writeShellScript "log-local-builds" ''
    echo "$OUT_PATHS" >> /var/log/local-builds
  '';

  clientConfig = writeText "clientConfig" ''
    { lib, ... }: {
      services.trustix-nix-cache = {
        enable = true;
        private-key = "/keys/cache-priv-key.pem";
        port = 9001;
      };
      nix = {
        binaryCaches = lib.mkForce [ "http//localhost:9001" ];
        binaryCachePublicKeys = lib.mkForce [ "clint://@binaryCachePubKey@" ];
      };
      services.trustix = {
        subscribers = [{
          protocol = "nix";
          publicKey = {
            type = "ed25519";
            pub = "@trustixPubKey@";
          };
        }];
        remotes = [ "grpc+http://alisha/" ];
        deciders.nix = {
          engine = "percentage";
          percentage.minimum = 66;
        };
      };
      nix.extraOptions = '''
        post-build-hook = ${log-local-builds}
      ''';
    }
  '';

  mkConfig =
    { config, trustixPubKeyPath, binaryCachePubKeyPath ? "/dev/null", }:
    writeShellScript "mkConfig" ''
      set -euxo pipefail
      mkdir -p /etc/nixos
      ${gnused}/bin/sed "
        s,@trustixPubKey@,$(< ${trustixPubKeyPath}),
        s,@binaryCachePubKey@,$(< ${binaryCachePubKeyPath}),
        " ${config} > /etc/nixos/local.nix
      cat > /etc/nixos/configuration.nix <<EOF
      {
        imports = [
          ${../lib/nixosTest-rebuild-switch.nix}
          ${trustixModule}
          ./local.nix
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
    clint = { pkgs, ... }: {
      imports = [
        ../lib/nixosTest-rebuild-switch.nix
        trustixModule
        "${binaryCacheKeyConfig}"
      ];
      system.extraDependencies = [
        pkgs.hello.inputDerivation
        pkgs.remarshal # For building trustix-config.toml
        (nixos {
          imports = [
            ../lib/nixosTest-rebuild-switch.nix
            trustixModule
            "${binaryCacheKeyConfig}"
            "${clientConfig}"
          ];
        }).toplevel
      ];
      virtualisation.diskSize = "1000";
      virtualisation.memorySize = "1G";
    };
  };
  testScript = ''
    from os import getenv

    alisha.wait_for_file("/keys/trustix-pub")
    alisha.copy_from_vm("/keys/trustix-pub")
    clint.copy_from_host(getenv("out") + "/trustix-pub", "/keys/alisha-signing-pub")

    alisha.succeed(
        "${
          mkConfig {
            config = publisherConfig;
            trustixPubKeyPath = "/keys/trustix-pub";
          }
        }",
        "nixos-rebuild switch --show-trace",
    )
    alisha.succeed("nix-build '<nixpkgs>' -A hello")

    clint.wait_for_file("/keys/cache-priv-key.pem")
    clint.succeed(
        "${
          mkConfig {
            config = clientConfig;
            trustixPubKeyPath = "/keys/alisha-signing-pub";
            binaryCachePubKeyPath = "/keys/cache-priv-key.pem";
          }
        }",
        "nixos-rebuild switch --show-trace",
    )
    clint.succeed("nix-build '<nixpkgs>' -A hello")
    clint.fail("grep hello /var/log/local-builds")
  '';
}
