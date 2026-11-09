# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."charlie" = {
    isNormalUser = true;
    description = "charlie";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # `sudo` strips NIX_PATH from the environment by default, so without this
  # `sudo nixos-rebuild switch` can't find `nixos-config` even though it's
  # the normal default — this pins it at the Nix daemon level instead of
  # relying on the caller's shell env. (NixOS list options like this one
  # merge/append with the module system's own default, they don't replace it.)
  nix.nixPath = [ "nixos-config=/etc/nixos/configuration.nix" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    webhook
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  # Key-only login: this host's SSH is reachable over a Cloudflare Tunnel
  # from the public internet, so password auth is off to rule out
  # brute-forcing from anywhere on the internet.
  services.openssh.settings.PasswordAuthentication = false;

  # Docker, needed to run vecna's docker-compose stack (mqtt-broker,
  # cync-lan, vecna) on this home-LAN box. See VECNA.md in the repo.
  virtualisation.docker.enable = true;

  # Single-node k3s cluster for vecna (see VECNA.md). Ships its own
  # Traefik ingress controller.
  services.k3s = {
    enable = true;
    role = "server";
  };

  # Cloudflare Tunnel: routes vecna.charlesragone.com and
  # deploy-vecna.charlesragone.com to this host without opening any
  # inbound port. Config/credentials live under charlie's home (created via
  # `cloudflared tunnel login/create/route dns`), so this runs as charlie,
  # not root.
  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel (bw-server)";
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

  # Token-gated deploy webhook for CI (see VECNA.md + vecna/scripts/hooks.json).
  # Lets production_vecna.yml trigger a deploy without SSH access to this box.
  systemd.services.vecna-deploy-webhook = {
    description = "vecna deploy webhook";
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "charlie";
      WorkingDirectory = "/home/charlie/monotheism";
      ExecStart = "${pkgs.webhook}/bin/webhook -hooks /home/charlie/monotheism/vecna/scripts/hooks.json -port 8088 -verbose";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

  # charlie already has full sudo (wheel) but needs it *passwordless* for
  # just `k3s` specifically, since the deploy webhook above runs unattended
  # (triggered over HTTP, no terminal to type a sudo password into) and
  # needs `k3s ctr`/`k3s kubectl` to land the deploy.
  security.sudo.extraRules = [
    {
      users = [ "charlie" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/k3s";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
