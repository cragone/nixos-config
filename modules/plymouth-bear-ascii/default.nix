{ pkgs ? import <nixpkgs> { } }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "plymouth-theme-bear-ascii";
  version = "1.0.0";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    themeDir="$out/share/plymouth/themes/bear-ascii"
    mkdir -p "$themeDir"
    cp "$src/bear.png" "$themeDir/bear.png"
    cp "$src/bear-ascii.script" "$themeDir/bear-ascii.script"
    substitute "$src/bear-ascii.plymouth" "$themeDir/bear-ascii.plymouth" \
      --subst-var-by THEME_DIR "$themeDir"

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "ASCII-art bear Plymouth boot theme";
    platforms = platforms.linux;
  };
}
