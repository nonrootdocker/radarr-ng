{
  description = "minimalbase-ng + sabnzbd service";

  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase-ng";
    sabnzbd-src = {
      url = "github:sabnzbd/sabnzbd";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, minimalbase, sabnzbd-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    # ----------------------------
    # SABnzbd Python environment
    # ----------------------------
    sabnzbdPython = pkgs.python3.withPackages (ps: [
      ps.apprise
      ps.cheetah3
      ps.configobj
      ps.cryptography
      ps.feedparser
      ps.pyopenssl
      ps.sabctools
    ]);

    sabnzbd = pkgs.stdenv.mkDerivation {
      pname = "sabnzbd";
      version = "latest";
      src = sabnzbd-src;

      buildInputs = [ sabnzbdPython ];

      # Clean, standard install phase (no custom python symlink hacks needed)
      installPhase = ''
        mkdir -p $out/app
        cp -r . $out/app/sabnzbd
      '';
    };

    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    sabAbi = pkgs.writeTextFile {
      name = "sabnzbd-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          # Point directly to the secure, immutable Nix store Python binary:
          exec = "${sabnzbdPython}/bin/python"; 
          args = [
            "/app/sabnzbd/SABnzbd.py"
            "--config-file"
            "/data/sabnzbd.ini"
            "--logging"
            "0"
            "--console"
            "--browser"
            "0"
          ];
        };
      };
      destination = "/app/main"; 
    };

    container-init = minimalbase.packages.${system}.container-init;

  in {
    packages.${system} = {
      default = self.packages.${system}.sabnzbd-image;
      sabnzbd-image = pkgs.dockerTools.buildImage {
        name = "minimalbase-ng";
        tag = "latest";

        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert

            container-init
            sabnzbd
            sabAbi
          ];
        };

        config = {
          Entrypoint = [ "${container-init}/bin/container-init" ];

          User = "1000:1000";

          Env = [
            "TZ=UTC"
            "LANG=en_US.UTF-8"
          ];
        };
      };
    };
  };
}
