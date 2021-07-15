{
  description = "Integration tests for trustix";

  inputs = {
    # nixpkgs.follows = "trustix/nixpkgs";  # When trustix becomes a flake
    # Until then:
    nixpkgs.url =
      "github:nixos/nixpkgs/f5e8bdd07d1afaabf6b37afc5497b1e498b8046f";

    trustix = {
      url = "github:tweag/trustix";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, trustix, }:
    let
      inherit (nixpkgs.lib) genAttrs;
      supportedSystems = [ "x86_64-linux" "i686-linux" "aarch64-linux" ];
      forAllSystems = genAttrs supportedSystems;

    in {

      lib = { prefetchNiv = import ./lib/prefetchNiv.nix; };

      checks = forAllSystems (system: {
        one-publisher = nixpkgs.legacyPackages."${system}".callPackage
          ./checks/one-publisher.nix {
            trustixSrc = (nixpkgs.legacyPackages."${system}".callPackage
              self.lib.prefetchNiv { }) trustix;
            trustix = (import trustix).packages.trustix;
          };
      });

    };
}
