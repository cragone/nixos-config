{
  description = "desktop and server configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
	home-manager = {
		url = "github:nix-community/home-manager/release-26.05";
		inputs.nixpkgs.follows = "nixpkgs";	
	};
	stylix = {
	    # url = "github:canavan-a/stylix/stable-base";
		url = "github:nix-community/stylix/release-26.05";	
	    inputs.nixpkgs.follows = "nixpkgs";
	};
	home-server.url = "github:canavan-a/home-server"; 
	open-lock.url = "github:canavan-a/open-lock";
	claude-code.url = "github:sadjow/claude-code-nix";
		fleetman.url = "github:canavan-a/fleetman";
	spinnyfetch.url = "github:canavan-a/spinnyfetch";
	horus-33 = {
		url = "github:canavan-a/horus-33";
		inputs.nixpkgs.follows = "nixpkgs";
	};
  };


  outputs = { self, nixpkgs, home-manager, stylix, home-server, open-lock, fleetman, nixpkgs-unstable, horus-33, ... } @ inputs:
  	let 
  	unstable = import nixpkgs-unstable {
  		system = "x86_64-linux";
  		config.allowUnfree = true;
  	};
	serverBase = [
		./common.nix
		./modules/server.nix
		./modules/micro.nix
		home-manager.nixosModules.home-manager
	];
	in
	{
	nixosConfigurations = {
		desktop = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			specialArgs = {inherit inputs unstable fleetman; };
			modules = [
				./common.nix
				./hardware-configuration-desktop.nix
				./modules/desktop.nix
				./modules/cb-cli.nix
				./modules/work.nix
				./modules/dir.nix
				./modules/micro.nix
				./modules/mqtt-broker.nix
				./modules/5gbandforce.nix
				./modules/claude-code-router.nix
				./cloudflare/cf.nix
				home-manager.nixosModules.home-manager
				stylix.nixosModules.stylix
				open-lock.nixosModules.default
			];	
		};
		server = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = serverBase ++[
				./hardware-configuration-M70s.nix
				./cloudflare/cf.nix
			];	
		};
		homeServer = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = serverBase ++ [
				./hardware-configuration-M70s.nix
				./cloudflare/cf.nix
				home-server.nixosModules.default
				{ 
					services.home-server.streamer.enable = true;	
				}
			];
		};

		bwServer = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = serverBase ++ [
				# hardware configuration file here
				
			];
		};

		neo = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = serverBase ++ [
				./hardware-configuration-neo.nix
				./cloudflare/cf.nix
				./modules/mqtt-broker.nix
				horus-33.nixosModules.default
				open-lock.nixosModules.default
				./modules/neoHomeServer.nix
			];
		};

		wrx = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = serverBase ++ [
				./hardware-configuration-wrx.nix
				./cloudflare/cf.nix
				./modules/wrx80-local-ai.nix
			];
		};

		# Generic, reusable Pi 5 host: build once, `dd` the resulting sdImage
		# to as many Pi 5 boards/SD cards as you want. Built against
		# nixpkgs-unstable rather than our usual nixpkgs (26.05) because Pi 5
		# support (mainline kernel dtbs + u-boot config.txt) only landed in
		# nixpkgs on 2026-07-03 and hasn't been backported to 26.05 yet. Uses
		# nixpkgs' own generic aarch64 sd-image module (mainline kernel +
		# u-boot + extlinux) -- the same mechanism the official NixOS
		# nixos-unstable aarch64 SD image uses, so flashing that official
		# image first and later `nixos-rebuild switch --flake`-ing to this
		# host from the Pi itself is a same-bootloader-scheme switch, not a
		# cross-bootloader one.
		raspi5 = nixpkgs-unstable.lib.nixosSystem {
			system = "aarch64-linux";
			specialArgs = { inherit inputs; };
			modules = [
				./common.nix
				./modules/dir.nix
				./modules/micro.nix
				./modules/raspi5.nix
				inputs.raspberry-pi-nix.nixosModules.raspberry-pi
				inputs.raspberry-pi-nix.nixosModules.sd-image
				home-manager.nixosModules.home-manager
			];
		};

	};
  };
}
