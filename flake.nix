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
    # SABnzbd package
    # ----------------------------
    sabnzbdPython = pkgs.python3.withPackages (ps: [
      ps.apprise
      ps.cheetah3
      ps.cryptography
      ps.feedparser
      ps.pyopenssl
    ]);
    sabnzbd = pkgs.stdenv.mkDerivation {
      pname = "sabnzbd";
      version = "latest";

      src = sabnzbd-src;

      buildInputs = [
        sabnzbdPython
      ];

      installPhase = ''
        mkdir -p $out/app

        if [ -f requirements.txt ]; then
          $out/app/python-venv/bin/pip install -r requirements.txt
        fi

        # SABnzbd source
        cp -r . $out/app/sabnzbd-src

        # REQUIRED ENTRYPOINT
        if [ -f SABnzbd.py ]; then
          cp SABnzbd.py $out/app/main.py
        else
          echo "ERROR: SABnzbd.py not found"
          exit 1
        fi
      '';
    };

    # ----------------------------
    # ABI generator (NO shell)
    # ----------------------------
    sabAbi = pkgs.writeText "sabnzbd-abi.json" (builtins.toJSON {
      version = 2;
      destination = "/app/main";
      process = {
        exec = "python";
        args = [
          "--config-file"
          "/data/sabnzbd.ini"
          "--logging"
          "0"
          "--console"
          "--browser"
          "0"
        ];
      };
    });

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

          Env = [
            "TZ=UTC"
            "LANG=en_US.UTF-8"
          ];
        };
      };
    };
  };
}
