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

        inherit (pkgs) lib;

        geojson = lib.naturalSort (
          builtins.attrNames (
            lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".json" n) (
              builtins.readDir ./static
            )
          )
        );

        generate-map-page =
          name: file:
          let
            file-contents = builtins.fromJSON (builtins.readFile ./static/${file});
            metadata = lib.findFirst (x: x.geometry == null) {
              properties = { };
            } file-contents.features;

            inherit (metadata) properties;

            header = pkgs.writers.writeYAML "header.yaml" properties;
          in
          ''
            echo '---' > content/${name}.md
            ${pkgs.coreutils}/bin/cat ${header} >> content/${name}.md
            echo '---' >> content/${name}.md
            echo '{{ leaflet_world(id="${name}", height="75%", width="100%", geojson="../${file}") }}' >> content/${name}.md
          '';
      in
      {
        apps.generate-pages = {
          type = "program";
          program = builtins.toString (
            pkgs.writers.writeBash "generate-pages" (
              lib.concatLines (
                [
                  # Create a json containing all routes
                  ''
                    ${pkgs.coreutils}/bin/rm static/all.json
                    ${pkgs.jq}/bin/jq '{"type": "FeatureCollection", "features": [.[] | .features[]]}' --slurp static/*.json > static/all.geojson
                    ${pkgs.coreutils}/bin/mv static/all.geojson static/all.json
                  ''
                  # Remove index file, and regenerate
                  ''
                    ${pkgs.coreutils}/bin/rm content/_index.md
                    echo '---' > content/_index.md
                    echo '---' >> content/_index.md
                    echo ' - [all](./all)' >> content/_index.md
                  ''
                  # Generate an all map
                  ''
                    ${generate-map-page "all" "all.json"}
                  ''
                ]
                ++ (builtins.map (
                  x:
                  let
                    prefix = builtins.replaceStrings [ ".json" ] [ "" ] x;
                  in
                  # Add entry to index page
                  # Regenerate own markdown file
                  ''
                    echo ' - [${prefix}](./${prefix})' >> content/_index.md

                    ${pkgs.coreutils}/bin/rm content/${prefix}.md

                    ${generate-map-page prefix x}
                  ''
                ) geojson)
              )
            )
          );
        };

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
