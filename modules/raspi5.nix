{ config, pkgs, lib, ... }:
{
	raspberry-pi-nix.board = "bcm2712";

	nixpkgs.hostPlatform = "aarch64-linux";

	# common.nix assumes a UEFI x86 host; the Pi boots straight off the
	# firmware-partition kernel.img that raspberry-pi-nix's sd-image module
	# manages itself, so neither of these apply here.
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
}
