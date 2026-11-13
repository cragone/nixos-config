{ config, pkgs, lib, modulesPath, ... }:
{
	imports = [ (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") ];

	nixpkgs.hostPlatform = "aarch64-linux";

	# common.nix assumes a UEFI x86 host; the Pi boots via the mainline
	# u-boot + extlinux setup that sd-image-aarch64.nix above already wires
	# up, so neither of these apply here.
	boot.loader.systemd-boot.enable = lib.mkForce false;
	boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

	# Overrides common.nix's shared "nixos" hostname so this is distinguishable
	# on the LAN. Reused across every board flashed from this same image, so
	# two Pi 5s online at once will collide on this name until one is renamed.
	networking.hostName = lib.mkForce "raspi5";

	# Key-only SSH so this is reachable headlessly right after first boot,
	# no console/passwd step needed. services.openssh.enable already comes
	# from common.nix.
	users.users.charlie.openssh.authorizedKeys.keys = [
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIND57RuWH0zzyDNEbnAusLPVC/UOG727D5aSUOm+n2QG charlie@monotheism-dev"
	];
	services.openssh.settings.PasswordAuthentication = false;

	# Hosts control-panel (see CONTROL-PANEL.md in the monotheism repo) as
	# a dedicated kiosk appliance: a touchscreen attached to this Pi shows
	# a fullscreen, native Rust (Slint) view of the app -- no browser/webview
	# at all -- that's its only job, so everything runs natively (no
	# k3s/Docker) for minimum latency.
	environment.systemPackages = with pkgs; [
		webhook cloudflared bun
		cargo rustc pkg-config
		fontconfig.dev freetype.dev libxkbcommon.dev wayland.dev mesa
	];

	# `cargo build`'s pkg-config probes (fontconfig-sys, freetype-sys, etc.)
	# don't automatically see -dev outputs placed in systemPackages the way
	# a nix-shell's buildInputs would -- PKG_CONFIG_PATH has to be set
	# explicitly.
	environment.variables.PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" (with pkgs; [
		fontconfig.dev freetype.dev libxkbcommon.dev wayland.dev mesa
	]);

	# kiosk/ is a plain `cargo build`, not a Nix-packaged derivation (matches
	# the ad-hoc native-build pattern deploy-local.sh already uses for the Go
	# backend and Bun frontend), so the resulting binary needs nix-ld to find
	# its runtime shared libraries (NixOS has no /usr/lib-style global path).
	programs.nix-ld = {
		enable = true;
		libraries = with pkgs; [ fontconfig freetype libxkbcommon wayland mesa ];
	};

	services.mosquitto = {
		enable = true;
		listeners = [
			{
				port = 1883;
				omitPasswordAuth = true;
				settings.allow_anonymous = true;
			}
		];
	};

	systemd.services.control-panel-web = {
		description = "control-panel web backend";
		after = [ "mosquitto.service" ];
		wants = [ "mosquitto.service" ];
		wantedBy = [ "multi-user.target" ];
		serviceConfig = {
			User = "charlie";
			WorkingDirectory = "/home/charlie/control-panel/web";
			Environment = [ "PORT=8080" "MQTT_BROKER=localhost" ];
			ExecStart = "/home/charlie/control-panel/web/main";
			Restart = "on-failure";
			RestartSec = "5s";
		};
	};

	# Fullscreen kiosk session: boots straight to tty1, no display manager,
	# no window manager chrome, no browser -- cage is a minimal Wayland
	# compositor that runs exactly one client fullscreen: the native Rust
	# (Slint) kiosk binary, GPU-accelerated via mainline Mesa's V3D/VC4
	# driver for the Pi 5, talking to the backend over a loopback WebSocket
	# for the lowest possible latency. Built by
	# monotheism/control-panel/scripts/deploy-local.sh (`cargo build
	# --release`), same as the Go backend and Bun frontend.
	services.cage = {
		enable = true;
		user = "charlie";
		program = "/home/charlie/control-panel/kiosk/target/release/control-panel-kiosk";
		environment = {
			# winit's wayland backend dlopen()s libwayland-client.so at
			# runtime rather than linking it directly; nix-ld's
			# NIX_LD_LIBRARY_PATH covers the binary's own startup deps but
			# not later dlopen() calls, which still go through the standard
			# LD_LIBRARY_PATH.
			LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [ wayland libxkbcommon fontconfig freetype mesa ]);
			# This board only exposes /dev/dri/card1 (vc4, display/KMS-only) --
			# no separate renderD* node -- so there's no real GPU render
			# capability available to EGL here (confirmed: cage's own
			# compositor falls back to its software pixman renderer for the
			# same reason). Slint's default backend tries GPU/femtovg first
			# and, on this hardware, ends up presenting nothing at all rather
			# than erroring -- force the software renderer instead, which
			# reliably renders as a plain SHM-backed buffer cage can compose.
			SLINT_BACKEND = "winit-software";
			# Set once bw-server exposes a LAN-only, unauthenticated route for
			# vecna's device list (see CONTROL-PANEL.md) -- until then the
			# kiosk falls back to a generic zone name.
			# VECNA_DEVICES_URL = "http://192.168.1.91:<port>/api/devices";
		};
	};

	# Config/credentials live under charlie's home (created via
	# `cloudflared tunnel login/create/route dns`), so this runs as charlie,
	# not root.
	systemd.services.cloudflared-tunnel = {
		description = "Cloudflare Tunnel (raspi5)";
		after = [ "network-online.target" ];
		wants = [ "network-online.target" ];
		wantedBy = [ "multi-user.target" ];
		serviceConfig = {
			User = "charlie";
			ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config /home/charlie/.cloudflared/config.yml run";
			Restart = "on-failure";
			RestartSec = "5s";
		};
	};

	# Token-gated deploy webhook for CI (see CONTROL-PANEL.md +
	# monotheism/control-panel/scripts/hooks.json). Lets control-panel's own
	# production.yml trigger a deploy without SSH access to this box.
	systemd.services.control-panel-deploy-webhook = {
		description = "control-panel deploy webhook";
		after = [ "network-online.target" ];
		wantedBy = [ "multi-user.target" ];
		serviceConfig = {
			User = "charlie";
			WorkingDirectory = "/home/charlie/monotheism";
			# Systemd's default PATH for services has none of bash/git/go/bun
			# on it, so deploy-local.sh (and everything it shells out to,
			# including the setuid `sudo` wrapper) needs this spelled out explicitly.
			Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
			ExecStart = "${pkgs.webhook}/bin/webhook -hooks /home/charlie/monotheism/control-panel/scripts/hooks.json -port 8089 -verbose";
			Restart = "on-failure";
			RestartSec = "5s";
		};
	};

	# charlie already has full sudo (wheel, from common.nix) but needs it
	# *passwordless* for a few specific things: restarting control-panel-web
	# after a deploy, and restarting the tunnel/webhook services, since the
	# webhook runs unattended (triggered over HTTP, no terminal to type a
	# sudo password into).
	security.sudo.extraRules = [
		{
			users = [ "charlie" ];
			commands = [
				{
					command = "/run/current-system/sw/bin/systemctl restart control-panel-web";
					options = [ "NOPASSWD" ];
				}
				{
					command = "/run/current-system/sw/bin/systemctl restart cage-tty1";
					options = [ "NOPASSWD" ];
				}
				{
					command = "/run/current-system/sw/bin/systemctl restart cloudflared-tunnel";
					options = [ "NOPASSWD" ];
				}
				{
					command = "/run/current-system/sw/bin/systemctl restart control-panel-deploy-webhook";
					options = [ "NOPASSWD" ];
				}
			];
		}
	];
}
