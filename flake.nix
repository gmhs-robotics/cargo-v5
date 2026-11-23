{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, flake-utils, naersk, rust-overlay, ... }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
      in rec {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pkg-config
            openssl
            libclang
            dbus
            udev
            (pkgs.rust-bin.nightly.latest.default.override {
              extensions = [ "rust-analyzer" "rust-src" "clippy" ];
            })
          ];

          LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
        };

        packages = let
          vexV5Serial = builtins.fetchTree {
            type = "github";
            owner = "vexide";
            repo = "vex-v5-serial";
            rev = "265dc8c71523e6e2fc9ca1d2448038ce57984a0b";
            narHash = "sha256-Rwdtv+uorT545dl+QF7QgK2R4laHLewtOzakl2aFY58=";
          };
          naersk' = pkgs.callPackage naersk {
            cargo = pkgs.rust-bin.stable.latest.default;
            rustc = pkgs.rust-bin.stable.latest.default;
          };
          build-cargo-v5 = { features ? [ ], ... }:
            pkgs.lib.checkListOfEnum "cargo-v5: features" [
              "field-control"
              "fetch-template"
            ] features naersk'.buildPackage {
              name = "cargo-v5";
              pname = "cargo-v5";
              version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;

              src = ./.;

              # Cargo's local dependency must be beside both naersk source trees.
              override = old: {
                preBuild = (old.preBuild or "") + ''
                  cp -R ${vexV5Serial.outPath} ../vex-v5-serial
                '';
              };

              passthru = {
                withFeatures = features: build-cargo-v5 { inherit features; };
              };

              cargoBuildOptions = opts:
                opts ++ [
                  "--features"
                  ''"${builtins.concatStringsSep " " features}"''
                ];

              nativeBuildInputs = with pkgs; [ pkg-config dbus udev ];
            };
        in rec {
          cargo-v5 = build-cargo-v5 { features = [ "field-control" ]; };
          default = cargo-v5;
        };

        apps = rec {
          cargo-v5 = flake-utils.lib.mkApp { drv = packages.cargo-v5; };
          default = cargo-v5;
        };
      }));
}
