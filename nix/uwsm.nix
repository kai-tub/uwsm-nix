{
  stdenv,
  lib,
  fetchFromGitHub,
  makeBinaryWrapper,
  meson,
  ninja,
  pkg-config,
  scdoc,
  python3,
  util-linux,
  newt,
  fuzzel,
  libnotify,
  bash,
  elogind,
}:
stdenv.mkDerivation rec {
  # there is no need to add the individual wayland compositors
  # as dependencies, as they should be called via the `.desktop` file
  # which should ensure that the binaries can be found!
  name = "uwsm";
  meta = {
    description = "A Universal Wayland Session Manager";
    homepage = "https://github.com/Vladimir-csp/uwsm";
    mainProgram = "uwsm";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [kai-tub];
  };
  version = "0.17.0";
  src = fetchFromGitHub {
    owner = "Vladimir-csp";
    repo = "uwsm";
    rev = "v${version}";
    hash = "sha256-M2j7l5XTSS2IzaJofAHct1tuAO2A9Ps9mCgAWKEvzoE=";
  };
  nativeBuildInputs = [
    makeBinaryWrapper
  ];
  buildInputs = [
    meson
    ninja
    pkg-config
    scdoc
  ];
  propagatedBuildInputs = [
    # these could be optional
    # and wrapped in a package
    util-linux # waitpid
    newt # whiptail
    fuzzel # fuzzel
    libnotify # notify
    bash # sh
    elogind # loginctl
    (python3.withPackages (
      ps: [
        ps.pydbus
        ps.dbus-python
        ps.pyxdg
      ]
    ))
  ];
  mesonFlags = [
    "--prefix=$out"
  ];
  dontConfigure = true;
  patches = [
    ./path.patch # upstream patch!
  ];
  buildPhase = ''
    runHook preBuild

    mkdir $out
    meson setup --prefix=$out build

    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall

    meson install -C build

    runHook postInstall
  '';
  postInstall = ''
    wrapProgram $out/bin/uwsm \
      --prefix PATH : ${
      lib.makeBinPath propagatedBuildInputs
    }
  '';
}
