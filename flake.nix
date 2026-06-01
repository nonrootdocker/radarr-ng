{
  description = "minimalbase-ng + jackett service";

  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase-ng";
    jackett-src = {
      # Matches the official Dockerfile's target release
      url = "https://github.com/Jackett/Jackett/releases/latest/download/Jackett.Binaries.LinuxMuslAMDx64.tar.gz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, minimalbase, jackett-src }:
  let
    system = "x86_64-linux";
    
    # Standard glibc-based packages
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };

    # Standard musl-based package set (guaranteed to evaluate correctly)
    muslPkgs = import nixpkgs {
      inherit system;
      crossSystem = {
        config = "x86_64-unknown-linux-musl";
      };
    };

    # ----------------------------
    # Jackett package
    # ----------------------------
    jackett = muslPkgs.stdenv.mkDerivation {
      pname = "jackett";
      version = "latest";
      src = jackett-src;

      nativeBuildInputs = [
        muslPkgs.autoPatchelfHook
      ];

      buildInputs = [
        muslPkgs.icu
        muslPkgs.curl
        muslPkgs.sqlite
        muslPkgs.openssl       # Musl-compiled OpenSSL 3.0
        muslPkgs.zlib          # Musl-compiled zlib
        muslPkgs.stdenv.cc.cc.lib
      ];

      # Clean, standard install phase (no custom python symlink hacks needed)
      installPhase = ''
        mkdir -p $out/app/Jackett
        cp -r . $out/app/Jackett/
      '';
    };

    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    jackettAbi = pkgs.writeTextFile {
      name = "jackett-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          # Point directly to the secure, immutable Nix store Jackett binary:
          exec = "${jackett}/app/Jackett/jackett"; 
          args = [
            "--DataFolder"
            "/data"
          ];
        };
      };
      destination = "/app/main"; 
    };

  in {
    packages.${system} = {
      default = self.packages.${system}.jackett-image;
      jackett-image = pkgs.dockerTools.buildImage {
        name = "minimalbase-ng";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;

        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert

            jackett
            jackettAbi
          ];
        };

        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];

          User = "1000:1000";

          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            # Points .NET to the musl-compiled runtime dependencies in the Nix Store
            "LD_LIBRARY_PATH=${muslPkgs.icu}/lib:${muslPkgs.openssl}/lib:${muslPkgs.zlib}/lib"
          ];
        };
      };
    };
  };
}
