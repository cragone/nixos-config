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

	# Hosts control-panel (see CONTROL-PANEL.md in the monotheism repo):
	# docker builds the image, k3s (containerd) runs it, a Cloudflare Tunnel
	# exposes it without opening any inbound port, and a token-gated webhook
	# lets CI trigger a deploy without SSH access to this box.
	virtualisation.docker.enable = true;
	services.k3s = {
		enable = true;
		role = "server";
	};

	environment.systemPackages = with pkgs; [ webhook cloudflared bun ];

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
			# Systemd's default PATH for services has none of bash/git/docker/k3s
			# on it, so deploy-local.sh (and everything it shells out to,
			# including the setuid `sudo` wrapper) needs this spelled out explicitly.
			Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
			ExecStart = "${pkgs.webhook}/bin/webhook -hooks /home/charlie/monotheism/control-panel/scripts/hooks.json -port 8089 -verbose";
			Restart = "on-failure";
			RestartSec = "5s";
		};
	};

	# charlie already has full sudo (wheel, from common.nix) but needs it
	# *passwordless* for a few specific things: `k3s` since the deploy
	# webhook runs unattended (triggered over HTTP, no terminal to type a
	# sudo password into) and needs `k3s ctr`/`k3s kubectl` to land the
	# deploy; and restarting the tunnel/webhook services, since editing
	# their config/hooks files doesn't itself trigger a restart the way
	# changing the unit definition would.
	security.sudo.extraRules = [
		{
			users = [ "charlie" ];
			commands = [
				{
					command = "/run/current-system/sw/bin/k3s";
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
