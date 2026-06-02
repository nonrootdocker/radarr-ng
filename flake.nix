{
  description = "minimalbase-ng + radarr service";
  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase-ng";
    radarr-src = {
      url = "https://radarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, minimalbase, radarr-src }:
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
    # Radarr package
    # ----------------------------
    radarr = pkgs.stdenv.mkDerivation {
      pname = "radarr";
      version = "latest";
      src = radarr-src;
      nativeBuildInputs = [
        pkgs.autoPatchelfHook
      ];
      buildInputs = [
        pkgs.icu
        pkgs.curl
        pkgs.sqlite
        opensslLib
        pkgs.zlib
        pkgs.lttng-ust_2_12
        pkgs.stdenv.cc.cc.lib
      ];
      unpackPhase = ''
        tar -xzf $src
      '';
      installPhase = ''
        mkdir -p $out/app
        cp -r . $out/app/
      '';
    };
    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      radarr:x:1000:1000:radarr:/data:/bin/sh
    '';
    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    radarrAbi = pkgs.writeTextFile {
      name = "radarr-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${radarr}/app/Radarr/Radarr";
          args = [
            "-nobrowser"
            "-data=/data"
          ];
        };
      };
      destination = "/app/main";
    };
  in {
    packages.${system} = {
      default = self.packages.${system}.radarr-image;
      radarr-image = pkgs.dockerTools.buildImage {
        name = "minimalbase-ng";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            pkgs.ffmpeg-headless
            radarr
            radarrAbi
          ];
        };
        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            "LD_LIBRARY_PATH=${pkgs.icu}/lib:${opensslLib}/lib:${pkgs.zlib}/lib:${pkgs.lttng-ust_2_12}/lib"
          ];
        };
      };
    };
  };
}
