{
  description = "Shell-agnostic git worktree session manager wrapping zmx";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/23d72dabcb3b12469f57b37170fcbc1789bd7457";
    nixpkgs-master.url = "github:NixOS/nixpkgs/b28c4999ed71543e71552ccfd0d7e68c581ba7e9";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
    shell.url = "github:friedenberg/eng?dir=devenvs/shell";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
      shell,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        mkScript = name: file:
          (pkgs.writeScriptBin name (builtins.readFile file)).overrideAttrs (old: {
            buildCommand = "${old.buildCommand}\n patchShebangs $out";
          });

        z = mkScript "z" ./bin/z;
        z-merge = mkScript "z-merge" ./bin/z-merge;
        z-completions = mkScript "z-completions" ./bin/z-completions;

        runtimeDeps = with pkgs; [
          gum
        ];
      in
      {
        packages.default = pkgs.symlinkJoin {
          name = "z";
          paths = [
            z
            z-merge
            z-completions
          ] ++ runtimeDeps;
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            for bin in z z-merge z-completions; do
              wrapProgram $out/bin/$bin --prefix PATH : $out/bin
            done
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            just
            gum
          ];

          inputsFrom = [
            shell.devShells.${system}.default
          ];

          shellHook = ''
            echo "z - dev environment"
          '';
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/z";
        };
      }
    );
}
