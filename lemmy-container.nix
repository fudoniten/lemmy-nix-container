{ config, lib, pkgs, ... }@toplevel:

with lib;
let
  cfg = config.services.lemmyContainer;

  lemmyImage = { ... }:
    { pkgs, ... }: {
      project.name = "lemmy";
      networks = {
        internal_network.internal = true;
        external_network.internal = false;
      };

      docker-compose.volumes = {
        postgres-data = { };
        lemmy-data = { };
      };

      services = {
        lemmy = { pkgs, ... }: {
          service = {
            restart = "always";
            volumes = [
              "postgres-data:/var/lib/postgres/data"
              "pictrs-data:/var/lib/pict-rs"
              "${cfg.admin-password-file}:${cfg.admin-password-file}"
            ];
            ports = "${toString cfg.port}:80";
            networks = [ "internal_network" "internal_network" ];
          };
          nixos = {
            useSystemd = true;
            configuration = {
              boot.tmp.useTmpfs = true;
              system.nssModules = mkForce [ ];
              services = {
                nscd.enable = false;
                postgresql.enable = true;
                pict-rs.enable = true;
                lemmy = {
                  enable = true;
                  database.createLocally = true;
                  adminPasswordFile = cfg.admin-password-file;
                  nginx.enable = true;
                  settings = {
                    email = {
                      smtp_server = cfg.smtp.host;
                      smtp_port = cfg.smtp.port;
                      smtp_from_address = "noreply@${cfg.hostname}";
                    };
                    hostname = cfg.hostname;
                    setup.site_name = cfg.site-name;
                  };
                };
                nginx = {
                  recommendedGzipSettings = true;
                  recommendedOptimisation = true;
                  recommendedProxySettings = true;
                  commonHttpConfig = ''
                    log_format with_response_time '$remote_addr - $remote_user [$time_local] '
                                 '"$request" $status $body_bytes_sent '
                                 '"$http_referer" "$http_user_agent" '
                                 '"$request_time" "$upstream_response_time"';
                    access_log /var/log/nginx/access.log with_response_time;
                  '';
                };
              };
            };
          };
        };
      };
    };
in {
  options.services.lemmyContainer = with types; {
    enable = mkEnableOption "Enable Lemmy server in a Podman container.";

    hostname = mkOption {
      type = str;
      description = "Host of the Lemmy server.";
    };

    port = mkOption {
      type = port;
      description = "Port on which to listen for requests.";
      default = 1234;
    };

    site-name = mkOption {
      type = str;
      description = "Name of the Lemmy site.";
    };

    admin-password-file = mkOption {
      type = str;
      description = "Path to a file containing the administrator password.";
    };

    smtp = {
      host = mkOption {
        type = str;
        description = "SMTP server hostname.";
      };

      port = mkOption {
        type = port;
        description = "SMTP server port.";
        default = 25;
      };
    };
  };

  config = mkIf cfg.enable {
    virtualisation.arion.projects.lemmy.settings = let image = lemmyImage { };
    in { imports = [ image ]; };

    services.nginx = {
      enable = true;
      virtualHosts."${cfg.hostname}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}/";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };
}
