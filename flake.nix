{
  description = "";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    devshell = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/devshell";
    };

    flake-compat = {
      flake = false;
      url = "github:edolstra/flake-compat";
    };

    git-hooks = {
      inputs = {
        flake-compat.follows = "flake-compat";
        gitignore.follows = "gitignore";
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:cachix/git-hooks.nix";
    };

    gitignore = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:hercules-ci/gitignore.nix";
    };
  };

  outputs =
    { self, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import self.inputs.nixpkgs {
          inherit system;
          overlays = with self.inputs; [
            devshell.overlays.default
          ];
        };
      in
      {
        checks = {
          git-hooks = self.inputs.git-hooks.lib.${system}.run {
            src = self;
            hooks = {
              actionlint.enable = true;
              deadnix = {
                enable = true;
                settings.edit = true;
              };
              nixfmt-rfc-style = {
                enable = true;
                settings.width = 80;
              };
              prettier = {
                enable = true;
                settings.write = true;
              };

              typos = {
                enable = true;
                settings = {
                  binary = false;
                  ignored-words = [
                    "authorization"
                    "authorized"
                    "authorizes"
                    "authorizing"
                    "characterized"
                    "defenses"
                    "organization"
                    "organizations"
                    "recognized"
                  ];
                  locale = "en-au";
                };
              };

              statix-write = {
                enable = true;
                name = "Statix Write";
                entry = "${pkgs.statix}/bin/statix fix";
                language = "system";
                pass_filenames = false;
              };

              trufflehog-verified = {
                enable = pkgs.stdenv.isLinux;
                name = "Trufflehog Search";
                entry = "${pkgs.trufflehog}/bin/trufflehog git file://. --since-commit HEAD --only-verified --fail";
                language = "system";
                pass_filenames = false;
              };
            };
          };
        };

        devShells.default = pkgs.devshell.mkShell {
          devshell.startup.git-hooks.text = self.checks.${system}.git-hooks.shellHook;

          name = "zola";

          packages = with pkgs; [
            actionlint
            conform
            deadnix
            nixfmt-rfc-style
            nodePackages.prettier
            statix
            trufflehog
            typos
            zola
          ];
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
