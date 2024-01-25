{ config, lib, pkgs, ... }@toplevel:

with lib;
let cfg = config.services.lemmyContainer;

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

    server-package = mkOption {
      type = package;
      description = "Package to use for the server.";
      default = pkgs.lemmy-server;
    };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store server state.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${state/directory}/postgres 0700 root root - -"
      "d ${state/directory}/pictrs 0700 root root - -"
    ];

    containers.lemmy = {
      autoStart = true;
      privateNetwork = true;
      forwardPorts = [{
        protocol = "tcp";
        hostPort = cfg.port;
        containerPort = 80;
      }];
      ephemeral = true;
      bindMounts = {
        "/var/lib/postgres/data" = {
          hostPath = "${cfg.state-directory}/postgres";
        };
        "/var/lib/private" = { hostPath = "${cfg.state-directory}/pictrs"; };
        "${cfg.admin-password-file}" = {
          isReadOnly = true;
          hostPath = cfg.admin-password-file;
        };
      };
      config = {
        boot.tmp.useTmpfs = true;
        services = {
          nscd.enable = false;
          postgresql.enable = true;
          pict-rs.enable = true;
          lemmy = {
            enable = true;
            database.createLocally = true;
            adminPasswordFile = cfg.admin-password-file;
            nginx.enable = true;
            server.package = cfg.server-package;
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
