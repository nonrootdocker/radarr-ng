{
  description = "minimalbase-ng + jackett service";

  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase-ng";
    jackett-src = {
      url = "https://github.com/Jackett/Jackett/releases/latest/download/Jackett.Binaries.LinuxAMDx64.tar.gz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, minimalbase, jackett-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };

    # ----------------------------
    # Jackett package
    # ----------------------------
    jackett = pkgs.stdenv.mkDerivation {
      pname = "jackett";
      version = "latest";
      src = jackett-src;

      nativeBuildInputs = [
        pkgs.autoPatchelfHook
      ];

      buildInputs = [
        pkgs.icu
        pkgs.curl
        pkgs.sqlite
        pkgs.openssl
        pkgs.openssl_1_1      # Explicitly added for legacy OpenSSL 1.1 compatibility
        pkgs.zlib
        pkgs.krb5              # Added for GSSAPI / SSL handshake operations
        pkgs.lttng-ust_2_12
        pkgs.stdenv.cc.cc.lib
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
            # Includes both OpenSSL 3.0 and OpenSSL 1.1 fallback paths
            "LD_LIBRARY_PATH=${pkgs.icu}/lib:${pkgs.openssl}/lib:${pkgs.openssl_1_1}/lib:${pkgs.zlib}/lib:${pkgs.krb5}/lib:${pkgs.lttng-ust_2_12}/lib"
          ];
        };
      };
    };
  };
}
