{
  description = "ThinkPhone Shinobu Kernel build environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      buildPackages = with pkgs; [
        bc
        bison
        ccache
        clang
        elfutils
        flex
        git
        gnumake
        elfutils.dev
        lld
        llvm
        openssl
        pahole
        perl
        pkg-config
        openssl.dev
        zlib
        zlib.dev
        python3
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = buildPackages;
        hardeningDisable = [ "zerocallusedregs" ];
      };

      packages.${system}.bronco-build = pkgs.buildFHSEnv {
        name = "bronco-build";
        targetPkgs = _: buildPackages;
        runScript = "bash";
      };
    };
}
