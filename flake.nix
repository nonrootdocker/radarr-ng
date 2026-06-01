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
    opensslLib = pkgs.openssl.out;
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
        opensslLib
        pkgs.zlib
        pkgs.krb5
        pkgs.lttng-ust_2_12
        pkgs.stdenv.cc.cc.lib
      ];
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
            "LD_LIBRARY_PATH=${pkgs.icu}/lib:${opensslLib}/lib:${pkgs.zlib}/lib:${pkgs.krb5}/lib:${pkgs.lttng-ust_2_12}/lib"
          ];
        };
      };
    };
  };
}
