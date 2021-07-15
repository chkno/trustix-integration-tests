# Pre-fetch niv-controlled sources so that we can use a niv-using package
# inside a nixosTest.

{ lib, stdenvNoCC, niv, runCommand, system, }:
src:
let
  inherit (lib) attrNames concatStringsSep filterAttrs hasPrefix mapAttrsToList;
  nivSources = filterAttrs (name: _: !(hasPrefix "__" name))
    (import (src + "/nix/sources.nix"));
in stdenvNoCC.mkDerivation {
  name = "niv-prefetched-source";
  inherit src;
  nativeBuildInputs = [ niv ];
  buildPhase = ''
    ${concatStringsSep "\n" (mapAttrsToList (name: info:
      "niv modify ${name} --attribute url=file://${
        if info.type == "tarball" then
        # Because niv
        #  * fetches nixpkgs with builtin.fetchTarball, even with
        #    --attribute builtin=false (it has to, to get fetchzip), and
        #  * only keeps the hash of the unpacked archive,
        # we have to let niv unpack it and verify the hash, then pack it back
        # up.  :(  Unpacking nixpkgs ends up being most of the test's disk space
        # and I/O.  If/when trustix switches from niv to flakes, this can all go
        # away--the test can just use the host's store paths directly.
          runCommand "niv-src-tarball-${name}.tar.gz" { } ''
            cd $(dirname ${info.outPath})
            tar czf $out --hard-dereference --sort=name $(basename ${info.outPath})
          ''
        else
          info.outPath
      }") nivSources)}
  '';
  installPhase = ''
    mkdir $out
    cp -r * $out
  '';
}
