{ pkgs ? import <nixpkgs> { config.allowUnfree = true; config.android_sdk.accept_license = true; } }:

let
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    cmdLineToolsVersion  = "11.0";
    toolsVersion         = "26.1.1";
    platformToolsVersion = "34.0.5";
    buildToolsVersions   = [ "34.0.0" ];
    includeEmulator      = false;
    includeSystemImages  = false;
    platformVersions     = [ "34" ];
    abiVersions          = [ "arm64-v8a" ];
    includeSources       = false;
    includeNDK           = true;
    ndkVersions          = [ "27.0.12077973" ];   # ← version requise par les plugins
  };

  androidSdk = androidComposition.androidsdk;

in pkgs.mkShell {
  name = "mamai-flutter-env";

  buildInputs = with pkgs; [
    flutter
    androidSdk
    jdk17
    git
    curl
    unzip
    which
    patchelf
    zlib
    autoPatchelfHook
    python312
    python312Packages.fastapi
    python312Packages.uvicorn
    python312Packages.httpx
    piper-tts
  ];

  shellHook = ''
    # ── SDK writable ──────────────────────────────────────────────────────────
    NIX_SDK="${androidSdk}/libexec/android-sdk"
    WRITABLE_SDK="$HOME/.android-sdk"
    if [ ! -d "$WRITABLE_SDK" ]; then
      echo "▶ Copie du SDK Android vers $WRITABLE_SDK..."
      cp -r "$NIX_SDK" "$WRITABLE_SDK"
      chmod -R u+w "$WRITABLE_SDK"
      echo "✓ SDK copié"
    fi

    export ANDROID_HOME="$WRITABLE_SDK"
    export ANDROID_SDK_ROOT="$WRITABLE_SDK"
    export ANDROID_NDK_HOME="$WRITABLE_SDK/ndk/27.0.12077973"
    export JAVA_HOME="${pkgs.jdk17}"
    export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
    export PATH="${pkgs.flutter}/bin:$PATH"

    # ── local.properties ──────────────────────────────────────────────────────
    LOCAL_PROPS="android/local.properties"
    if [ -f "$LOCAL_PROPS" ]; then
      sed -i "s|^sdk.dir=.*|sdk.dir=$ANDROID_HOME|" "$LOCAL_PROPS"
      sed -i "s|^ndk.dir=.*|ndk.dir=$ANDROID_NDK_HOME|" "$LOCAL_PROPS"
    else
      printf "sdk.dir=$ANDROID_HOME\nndk.dir=$ANDROID_NDK_HOME\n" > "$LOCAL_PROPS"
    fi

    # ── Patch AAPT2 avec patchelf ─────────────────────────────────────────────
    # AAPT2 est un binaire ELF précompilé pour "generic linux" → incompatible NixOS
    # On le patche pour qu'il utilise le dynamic linker et les libs Nix
    INTERP="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
    RPATH="${pkgs.lib.makeLibraryPath [ pkgs.zlib pkgs.stdenv.cc.cc.lib ]}"

    patch_aapt2() {
      find "$HOME/.gradle/caches" -name "aapt2" -type f 2>/dev/null | while read bin; do
        if file "$bin" | grep -q ELF; then
          patchelf --set-interpreter "$INTERP" --set-rpath "$RPATH" "$bin" 2>/dev/null \
            && echo "✓ AAPT2 patché : $bin" \
            || true
        fi
      done
    }
    patch_aapt2

    flutter config --no-analytics > /dev/null 2>&1 || true

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║        mamAI — Flutter Build Env         ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║  flutter build apk --release             ║"
    echo "║    --target-platform android-arm64       ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "ANDROID_HOME     : $ANDROID_HOME"
    echo "ANDROID_NDK_HOME : $ANDROID_NDK_HOME"
    echo "JAVA_HOME        : $JAVA_HOME"
    echo ""
  '';
}
