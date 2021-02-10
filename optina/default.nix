{ lib, config, pkgs, ... }:


with lib;

let
  secrets = import ../load-secrets.nix;
  shared = import ../shared.nix;
  custom_modules = (import ../modules/modules-list.nix);
  hydraRev = "1d613d05814f6074048933fe6c422ea059ce4130";
  hydraSrc = pkgs.fetchFromGitHub {
    owner = "input-output-hk";
    repo = "hydra";
    sha256 = "1wwy9llp10i1c793dlba2iryr54yahqxqfdsl3m1zq698v92ssw3";
    rev = hydraRev;
  };
  hydraSrc' = {
    outPath = hydraSrc;
    rev = hydraRev;
    revCount = 1234;
  };
  hydra-fork = (import (hydraSrc + "/release.nix") { nixpkgs = pkgs.path; hydraSrc = hydraSrc'; }).build.x86_64-linux;
  patched-hydra = pkgs.hydra.overrideDerivation (drv: {
    patches = [
    ];
  });
  netboot_root = pkgs.runCommand "nginxroot" {} ''
    mkdir -pv $out
    cat <<EOF > $out/boot.php
    <?php
    if (\$_GET['version'] == "") {
    ?>
    #!ipxe
    chain tftp://10.40.33.1/undionly.kpxe
    <?php
    } else {
    ?>
    #!ipxe
    chain netboot/netboot.ipxe
    <?php
    }
    ?>
    EOF
    ln -sv ${netboot} $out/netboot
  '';
  netboot = let
    build = (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        (pkgs.path + "/nixos/modules/installer/netboot/netboot-minimal.nix")
        ./justdoit.nix
        module
      ];
    }).config.system.build;
  in pkgs.symlinkJoin {
    name = "netboot";
    paths = with build; [ netbootRamdisk kernel netbootIpxeScript ];
  };
  module = {
    kexec.justdoit = {
      luksEncrypt = false;
      rootDevice = "/dev/sda";
      swapSize = 256;
      bootSize = 64;
    };
  };
in {
  imports =
    [
      ./hardware.nix
    ] ++ custom_modules;
    _module.args = {
      inherit secrets shared;
    };

  nix = let
    buildMachines = import ../build-machines.nix;
  in {
    sshServe = {
      enable = true;
      keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC6A3QRIK9XfLf/eDYb9Z4UO7iTmH7Gy3xwHphDx/ZEF9xZ6NuSsotihNZCpGIq2W3G7lx+3TlJW4WuI2GUHr9LZRsI+Z7T2+tSEtQZ1sE4p4rvlkNBzORobfrjXWs32Wd4ZH1i9unJRY6sFouWHt0ejjpnH49F8q5grTZALzrwh+Rz+Wj7Z1No7FccVMB15EtROq9jFQjP1Yqc+jScSFhgurHBpQbyJZXHXaelwVwLLM7DfDyLCDLgkB+1PDDMmfCMFEdV4oTMWmN6kZb52ko4B5ygzFg/RgOe73yYv9FRxUZK3kQQQfl4/VOIB8DhJieD/2VfmjCI0Q46xnia0rdz root@sarov" ];
    };
    buildMachines = [
      buildMachines.linux.optina
    ];
    binaryCaches = [ "https://cache.nixos.org" "https://hydra.iohk.io" ]; # "https://hydra.wedlake.lan" ];
    binaryCachePublicKeys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" "hydra.wedlake.lan:C3xufTQ7w2Y6VHtf+dyA6NmQPiQjwIDEavJNmr97Loo=" ];
    extraOptions = ''
      allowed-uris = https://github.com/NixOS/nixpkgs/archive https://github.com/input-output-hk
    '';
  };

  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  boot.loader = {
    grub = {
      efiSupport = true;
      device = "nodev";
      memtest86.enable = true;
      efiInstallAsRemovable = true;
    };
    efi = {
      canTouchEfiVariables = false;
    };
  };
  boot.supportedFilesystems = [ "zfs" ];
  profiles.weechat = secrets.weechat-configs;
  #profiles.vim.enable = false;
  profiles.zsh.enable = true;
  profiles.tmux.enable = true;
  profiles.passopolis.enable = true;

  networking = {
    hostName = "optina";
    domain = "wedlake.lan";
    hostId = "1768b40b";
    interfaces.enp2s0.ipv4.addresses = [ { address = "10.40.33.20"; prefixLength = 24; } ];
    defaultGateway = "10.40.33.1";
    nameservers = [ "10.40.33.1" "8.8.8.8" ];
    extraHosts =
    ''
      10.233.1.2 rtorrent.optina.local
    '';
    nat = {
      enable = true;
      internalInterfaces = ["ve-+"];
      externalInterface = "enp2s0";
    };
    firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = [
        53
        80
        139
        443
        445
        631
        3000   # grafana
        3001   # cardano-node
        4444
        5601   # kibana
        5900
        5951
        5952
        6600
        6667
        8000
        8080
        8083
        8086
        8091
        9090
        9092
        9093
        9100
        9200   # elasticsearch
        22022
        24000
        32400  # plex
        5201   # iperf
      ];
      allowedUDPPorts = [ 53 137 138 1194 500 4500 ];
    };
  };

  security.pki.certificates = [ shared.wedlake_ca_cert ];

  nixpkgs = {
    config = {
      allowUnfree = true;
      # required for mongodb 3.4
      permittedInsecurePackages = ["openssl-1.0.2u"];
      packageOverrides = pkgs: rec {
        weechat = pkgs.weechat.override {
          configure = {availablePlugins, ...}: {
            plugins = with availablePlugins; [
                    (python.withPackages (ps: with ps; [ websocket_client ]))
                    perl ruby
            ];
          };
        };
      };
    };
    overlays = [
      #(import ../overlays/plex.nix)
    ];
  };

  environment.systemPackages = with pkgs; [
    kvm
    aspell
    aspellDicts.en
    ncdu
    unrar
    conky
    #chromium
    unzip
    zip
    gnupg
    gnupg1compat
    weechat
    rxvt_unicode
    tcpdump
    nix-prefetch-git
    ncmpc
    git
    fasd
    dnsutils
    #openssl
    powerdns
    virtmanager
  ];

  services = {
    cardano-node = {
      enable = false;
      environment = "ff";
      hostAddr = "0.0.0.0";
      topology =  builtins.toFile "topology.json" (builtins.toJSON {
        Producers = [
          {
            addr = "10.40.33.1";
            port = 3001;
            valency = 1;
          }
        ];
      });
      nodeConfig = config.services.cardano-node.environments.alpha1.nodeConfig // {
        hasPrometheus = [ "127.0.0.1" 12798 ];
        setupScribes = [{
          scKind = "JournalSK";
          scName = "cardano";
          scFormat = "ScText";
        }];
        defaultScribes = [
          [
            "JournalSK"
            "cardano"
          ]
        ];
      };
      kesKey = "/var/run/keys/cardano-kes";
      vrfKey = "/var/run/keys/cardano-vrf";
      operationalCertificate = "/var/run/keys/cardano-opcert";
    };
    udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="74:d4:35:9b:84:62", NAME="enp2s0"
    '';
    zookeeper = {
      enable = false;
    };
    apache-kafka = {
      enable = false;
      extraProperties = ''
        offsets.topic.replication.factor = 1
      '';
      hostname = "optina.wedlake.lan";
      zookeeper = "localhost:2181";
    };
    elasticsearch = {
      enable = false;
      listenAddress = "0";
      #plugins = with pkgs.elasticsearchPlugins; [ search_guard ];
    };

    kibana = {
      enable = false;
      listenAddress = "optina.wedlake.lan";
      elasticsearch.url = "http://localhost:9200";
    };

    #hledger = {
    #  api = {
    #    enable = true;
    #    listenPort = "8001";
    #  };
    #  web = {
    #    enable = true;
    #    listenPort = "8002";
    #    baseURL = "https://hledger.wedlake.lan/";
    #  };
    #};

    journalbeat = {
      enable = false;
      extraConfig = ''
      journalbeat:
        seek_position: cursor
        cursor_seek_fallback: tail
        write_cursor_state: true
        cursor_flush_period: 5s
        clean_field_names: true
        convert_to_numbers: false
        move_metadata_to_field: journal
        default_type: journal
      output.kafka:
        hosts: ["optina.wedlake.lan:9092"]
        topic: KAFKA-LOGSTASH-ELASTICSEARCH
      '';
    };

    logstash = {
      enable = false;
      inputConfig = ''
        kafka {
          zk_connect => "localhost:2181"
          topic_id => "KAFKA-LOGSTASH-ELASTICSEARCH"
          codec => json {}
        }
      '';
      outputConfig = ''
        elasticsearch {
            index  => "systemd-logs-%{+YYYY.MM.dd}"
            hosts => ["localhost:9200"]
            sniffing => false
         }
      '';
    };

    xserver = {
      autorun = true;
      enable = true;
      layout = "us";
      windowManager.i3 = {
        enable = true;
        #extraSessionCommands = ''
        #  ${pkgs.feh} --bg-scale /home/sam/photos/20170503_183237.jpg
        #'';
        package = pkgs.i3-gaps;
      };
      displayManager.defaultSession = "none+i3";
      displayManager.lightdm = {
        enable = true;
        background = "/etc/lightdm/background.jpg";
      };
    };
    bitlbee.enable = true;
    gitea = {
      enable = true;
      domain = "git.wedlake.lan";
      appName = "Personal Git Server";
      httpAddress = "127.0.0.1";
      rootUrl = "https://git.wedlake.lan";
      httpPort = 3001;
      database = {
        type = "postgres";
        port = 5432;
        passwordFile = "/run/keys/gitea-dbpass";
      };
    };
    mongodb.enable = true;
    unifi = {
      enable = true;
      unifiPackage = pkgs.unifiStable;
    };
    #telegraf = {
    #  enable = true;
    #  extraConfig = {
    #    outputs = {
    #      influxdb = [{
    #        urls = ["http://localhost:8086"];
    #        database = "telegraf";
    #      }];
    #      prometheus_client = [{
    #        listen = ":9101";
    #      }];
    #    };
    #    inputs = {
    #      cpu = [{}];
    #      disk = [{}];
    #      diskio = [{}];
    #      kernel = [{}];
    #      mem = [{}];
    #      swap = [{}];
    #      netstat = [{}];
    #      nstat = [{}];
    #      ntpq = [{}];
    #      procstat = [{}];
    #    };
    #  };
    #};
    prometheus.exporters = {
      blackbox = {
        enable = true;
        configFile = pkgs.writeText "blackbox-exporter.yaml" (builtins.toJSON {
        modules = {
          https_2xx = {
            prober = "http";
            timeout = "5s";
            http = {
              fail_if_not_ssl = true;
            };
          };
          htts_2xx = {
            prober = "http";
            timeout = "5s";
          };
          ssh_banner = {
            prober = "tcp";
            timeout = "10s";
            tcp = {
              query_response = [ { expect = "^SSH-2.0-"; } ];
            };
          };
          tcp_v4 = {
            prober = "tcp";
            timeout = "5s";
            tcp = {
              preferred_ip_protocol = "ip4";
            };
          };
          tcp_v6 = {
            prober = "tcp";
            timeout = "5s";
            tcp = {
              preferred_ip_protocol = "ip6";
            };
          };
          icmp_v4 = {
            prober = "icmp";
            timeout = "60s";
            icmp = {
              preferred_ip_protocol = "ip4";
            };
          };
          icmp_v6 = {
            prober = "icmp";
            timeout = "5s";
            icmp = {
              preferred_ip_protocol = "ip6";
            };
          };
        };
      });
      };
      #surfboard = {
      #  enable = true;
      #};
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
          "tcpstat"
          "conntrack"
          "diskstats"
          "entropy"
          "filefd"
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "netstat"
          "stat"
          "time"
          "vmstat"
          "logind"
          "interrupts"
          "ksmd"
        ];
      };
      unifi = {
        enable = false;
        unifiAddress = "https://unifi.wedlake.lan";
        unifiUsername = "prometheus";
        unifiPassword = secrets.unifi_password_ro;
        openFirewall = true;
      };
    };
    prometheus = {
      enable = true;
      extraFlags = [
        "--storage.tsdb.retention.time 8760h"
      ];
      alertmanagers = [ {
        scheme = "http";
        path_prefix = "/";
        static_configs = [ {
          targets = [ "optina.wedlake.lan:9093" ];
        } ];
      } ];
      rules = [ (builtins.toJSON {
        groups = [
          {
            name = "system";
            rules = [
              {
                alert = "node_down";
                expr = "up == 0";
                for = "5m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Node is down.";
                  description = "{{$labels.alias}} has been down for more than 5 minutes.";
                };
              }
              {
                alert = "node_systemd_service_failed";
                expr = "node_systemd_unit_state{state=\"failed\"} == 1";
                for = "4m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Service {{$labels.name}} failed to start.";
                  description = "{{$labels.alias}} failed to (re)start service {{$labels.name}}.";
                };
              }
              {
                alert = "node_filesystem_full_90percent";
                expr = "sort(node_filesystem_free_bytes{device!=\"ramfs\"} < node_filesystem_size_bytes{device!=\"ramfs\"} * 0.1) / 1024^3";
                for = "5m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Filesystem is running out of space soon.";
                  description = "{{$labels.alias}} device {{$labels.device}} on {{$labels.mountpoint}} got less than 10% space left on its filesystem.";
                };
              }
              {
                alert = "node_filesystem_full_in_4h";
                expr = "predict_linear(node_filesystem_free_bytes{device!=\"ramfs\",device!=\"tmpfs\",fstype!=\"autofs\",fstype!=\"cd9660\"}[4h], 4*3600) <= 0";
                for = "5m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Filesystem is running out of space in 4 hours.";
                  description = "{{$labels.alias}} device {{$labels.device}} on {{$labels.mountpoint}} is running out of space of in approx. 4 hours";
                };
              }
              {
                alert = "node_filedescriptors_full_in_3h";
                expr = "predict_linear(node_filefd_allocated[1h], 3*3600) >= node_filefd_maximum";
                for = "20m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}} is running out of available file descriptors in 3 hours.";
                  description = "{{$labels.alias}} is running out of available file descriptors in approx. 3 hours";
                };
              }
              {
                alert = "node_load1_90percent";
                expr = "node_load1 / on(alias) count(node_cpu_seconds_total{mode=\"system\"}) by (alias) >= 0.9";
                for = "1h";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Running on high load.";
                  description = "{{$labels.alias}} is running with > 90% total load for at least 1h.";
                };
              }
              {
                alert = "node_cpu_util_90percent";
                expr = "100 - (avg by (alias) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) >= 90";
                for = "1h";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: High CPU utilization.";
                  description = "{{$labels.alias}} has total CPU utilization over 90% for at least 1h.";
                };
              }
              {
                alert = "node_ram_using_99percent";
                expr = "node_memory_MemFree_bytes + node_memory_Buffers_bytes + node_memory_Cached_bytes < node_memory_MemTotal_bytes * 0.01";
                for = "30m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Using lots of RAM.";
                  description = "{{$labels.alias}} is using at least 90% of its RAM for at least 30 minutes now.";
                };
              }
              {
                alert = "node_swap_using_80percent";
                expr = "node_memory_SwapTotal_bytes - (node_memory_SwapFree_bytes + node_memory_SwapCached_bytes) > node_memory_SwapTotal_bytes * 0.8";
                for = "10m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Running out of swap soon.";
                  description = "{{$labels.alias}} is using 80% of its swap space for at least 10 minutes now.";
                };
              }
              {
                alert = "node_time_unsync";
                expr = "abs(node_timex_offset_seconds) > 0.050 or node_timex_sync_status != 1";
                for = "1m";
                labels = {
                  severity = "page";
                };
                annotations = {
                  summary = "{{$labels.alias}}: Clock out of sync with NTP";
                  description = "{{$labels.alias}} Local clock offset is too large or out of sync with NTP";
                };
              }
            ];
          }
        ];
      })];
      scrapeConfigs = [
        {
          job_name = "prometheus";
          scrape_interval = "5s";
          static_configs = [
            {
              targets = [
                "localhost:9090"
              ];
            }
          ];
        }
        #{
        #  job_name = "cardano-node";
        #  scrape_interval = "10s";
        #  static_configs = [
        #    {
        #      targets = [ "10.40.33.1:12798" ];
        #      labels = { alias = "portal"; };
        #    }
        #    {
        #      targets = [ "127.0.0.1:12798" ];
        #      labels = { alias = "optina"; };
        #    }
        #  ];
        #}
        {
          job_name = "node";
          scrape_interval = "10s";
          static_configs = [
            {
              targets = [
                "portal.wedlake.lan:9100"
              ];
              labels = {
                alias = "portal.wedlake.lan";
              };
            }
            {
              targets = [
                "optina.wedlake.lan:9100"
              ];
              labels = {
                alias = "optina.wedlake.lan";
              };
            }
            {
              targets = [
                "prod01.wedlake.lan:9100"
              ];
              labels = {
                alias = "prod01.wedlake.lan";
              };
            }
          ];
        }
        #{
        #  job_name = "surfboard";
        #  scrape_interval = "5s";
        #  static_configs = [
        #    {
        #      targets = [
        #        "localhost:9239"
        #      ];
        #    }
        #  ];
        #}
        #{
        #  job_name = "unifi";
        #  scrape_interval = "10s";
        #  static_configs = [
        #    {
        #      targets = [
        #        "localhost:9130"
        #      ];
        #      labels = {
        #        alias = "unifi.wedlake.lan";
        #      };
        #    }
        #  ];
        #}
        {
          job_name = "blackbox";
          scrape_interval = "60s";
          metrics_path = "/probe";
          params = {
            module = [ "ssh_banner" ];
          };
          static_configs = [
            {
              targets = [
                "73.230.94.119"
              ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              regex = "(.*)(:.*)?";
              replacement = "\${1}:22";
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              source_labels = [];
              target_label = "__address__";
              replacement = "127.0.0.1:9115";
            }
          ];
        }
        {
          job_name = "icmp-sarov";
          scrape_interval = "10s";
          metrics_path = "/probe";
          params = {
            module = [ "icmp_v4" ];
          };
          static_configs = [
            {
              targets = [
                "10.40.33.165"
                "10.40.33.167"
              ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              regex = "(.*)";
              replacement = "\${1}";
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              source_labels = [];
              target_label = "__address__";
              replacement = "127.0.0.1:9115";
            }
          ];
        }
      ];
    };
    prometheus.alertmanager = {
      enable = true;
      listenAddress = "0.0.0.0";
      configuration = {
        "global" = {
          "smtp_smarthost" = "smtp.gmail.com:587";
          "smtp_from" = "alertmanager@samleathers.com";
          "smtp_auth_username" = "disasm@gmail.com";
          "smtp_auth_password" = secrets.alertmanager_smtp_pw;
        };
        "route" = {
          "group_by" = [ "alertname" "alias" ];
          "group_wait" = "30s";
          "group_interval" = "2m";
          "repeat_interval" = "4h";
          "receiver" = "team-admins";
        };
        "receivers" = [
          {
            "name" = "team-admins";
            "email_configs" = [
            {
                "to"            = "disasm@gmail.com";
                "send_resolved" = true;
              }
            ];
            "pagerduty_configs" = [
              {
                "service_key" = secrets.pagerduty_token;
              }
            ];
          }
        ];
      };
    };
    grafana = {
      enable = true;
      addr = "0.0.0.0";
    };
    phpfpm = {
      #phpPackage = pkgs.php71;
      pools = {
        mypool = {
          user = "nginx";
          settings = {
            "pm" = "dynamic";
            "pm.max_children" = 5;
            "pm.start_servers" = 1;
            "pm.min_spare_servers" = 1;
            "pm.max_spare_servers" = 2;
            "pm.max_requests" = 50;
          };
        };
      };
      phpOptions =
      ''
      [opcache]
      opcache.enable=1
      opcache.memory_consumption=128
      opcache.interned_strings_buffer=8
      opcache.max_accelerated_files=4000
      opcache.revalidate_freq=60
      opcache.fast_shutdown=1
      '';
        };
        nginx = {
        enable = true;
        virtualHosts = {
          "netboot.wedlake.lan" = {
            root = netboot_root;
            extraConfig = ''
              location ~ [^/]\.php(/|$) {
                fastcgi_pass unix:${config.services.phpfpm.pools.mypool.socket};
              }
            '';
          };
          "hledger.wedlake.lan" = {
            forceSSL = true;
            sslCertificate = "/data/ssl/hledger.wedlake.lan.crt";
            sslCertificateKey = "/data/ssl/hledger.wedlake.lan.key";
            locations."/api".extraConfig = ''
              proxy_pass http://localhost:8001/api;
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header  X-Real-IP         $remote_addr;
              proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            '';
            locations."/".extraConfig = ''
              proxy_pass http://localhost:8002/;
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header  X-Real-IP         $remote_addr;
              proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            '';
          };
          "crate.wedlake.lan" = {
            forceSSL = true;
            sslCertificate = "/data/ssl/nginx.crt";
            sslCertificateKey = "/data/ssl/nginx.key";
            locations."/".extraConfig = ''
              proxy_pass http://localhost:8089/;
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header  X-Real-IP         $remote_addr;
              proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            '';
            locations."/weechat" = {
              proxyPass = "http://127.0.0.1:9001/weechat";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_read_timeout 4h;
              '';
            };
          };
          "storage.wedlake.lan" = {
            forceSSL = false;
            root = "/var/storage";
          };
          "unifi.wedlake.lan" = {
            forceSSL = true;
            sslCertificate = "/data/ssl/unifi.wedlake.lan.crt";
            sslCertificateKey = "/data/ssl/unifi.wedlake.lan.key";
            locations."/".extraConfig = ''
              proxy_set_header Referer "";
              proxy_pass https://localhost:8443/;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forward-For $proxy_add_x_forwarded_for;
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
            '';
          };
          "git.wedlake.lan" = {
            forceSSL = true;
            sslCertificate = "/data/ssl/git.wedlake.lan.crt";
            sslCertificateKey = "/data/ssl/git.wedlake.lan.key";
            locations."/".extraConfig = ''
              proxy_pass http://localhost:3001/;
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header  X-Real-IP         $remote_addr;
              proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            '';
          };
          "hydra.wedlake.lan" = {
            forceSSL = true;
            sslCertificate = "/data/ssl/hydra.wedlake.lan.crt";
            sslCertificateKey = "/data/ssl/hydra.wedlake.lan.key";
            locations."/".extraConfig = ''
              proxy_pass http://localhost:3002/;
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header  X-Real-IP         $remote_addr;
              proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            '';
          };
        };
      };

      samba = {
        enable = true;
        shares = {
          meganbackup =
          { path = "/data/backups/other/megan";
          "valid users" = "sam megan";
          writable = "yes";
          comment = "Megan's Backup";
          };
          musicdrive =
          { path = "/data/pvr/music";
          "valid users" = "sam megan nursery";
          writable = "yes";
          comment = "music share";
          };
          };
          extraConfig = ''
          guest account = nobody
          map to guest = bad user
          '';
        };
        printing = {
          enable = true;
          drivers = [ pkgs.hplip ];
          defaultShared = true;
          browsing = true;
          listenAddresses = [ "*:631" ];
          extraConf = ''
            <Location />
            Order allow,deny
            Allow from all
            </Location>
          '';
        };

        mopidy = {
          enable = false;
          configuration = ''
            [local]
            enabled = true
            media_dir = /data/pvr/music
          '';
        };
        mpd = {
          enable = true;
          musicDirectory = "/data/pvr/music";
          extraConfig = ''
            log_level "verbose"
            restore_paused "no"
            metadata_to_use "artist,album,title,track,name,genre,date,composer,performer,disc,comment"
            bind_to_address "10.40.33.20"
            password "${secrets.mpd_pw}@admin,read,add,control"

            input {
            plugin "curl"
            }
            audio_output {
            type        "shout"
            encoding    "ogg"
            name        "Icecast stream"
            host        "prophet.samleathers.com"
            port        "8000"
            mount       "/mpd.ogg"
            public      "yes"
            bitrate     "192"
            format      "44100:16:1"
            user        "mpd"
            password    "${secrets.mpd_icecast_pw}"
            }
            audio_output {
            type "alsa"
            name "fake out"
            driver "null"
            }
          '';
        };
        postgresql = {
          enable = true;
          # Only way to get passopolis to work
          # Lock this down once we migrate away from passopolis
          authentication = ''
            local passopolis all ident map=passopolis-users
            local gitea all ident map=gitea-users
          '';
          identMap = ''
            hydra-users sam hydra
            passopolis-users passopolis passopolis
            gitea-users gitea gitea
          '';
        };
        postgresqlBackup.enable = true;
        # Plex
        plex = {
          enable = true;
          #package = pkgs.plex.overrideAttrs (x: {
          #  src = pkgs.fetchurl {
          #    url = let
          #      version = "1.18.8.2527";
          #      vsnHash = "740d4c206";

          #    in "https://downloads.plex.tv/plex-media-server-new/${version}-${vsnHash}/plexmediaserver-${version}-${vsnHash}.x86_64.rpm";
          #    sha256 = "0h2w5xqw8rffffbibdwj8bi7vb72yzhvna5hrb8frp6fbkrhds4f";
          #  };
          #});
        };
        hydra = {
          enable = true;
          #package = hydra-fork;
          hydraURL = "https://hydra.wedlake.lan";
          notificationSender = "disasm@gmail.com";
          minimumDiskFree = 2;
          minimumDiskFreeEvaluator = 1;
          port = 3002;
          useSubstitutes = true;
          extraConfig = ''
            store-uri = file:///nix/store?secret-key=/etc/nix/hydra.wedlake.lan-1/secret
            binary_cache_secret_key_file = /etc/nix/hydra.wedlake.lan-1/secret
            <github_authorization>
              disassembler = token ${secrets.github_token}
            </github_authorization>
            <githubstatus>
              #useShortContext = 1
              jobs = nixos-configs:nixos-configs.*
              inputs = nixos-configs
              excludeBuildFromContext = 1
            </githubstatus>
          '';
        };

      };
      systemd.services.hydra-manual-setup = {
        description = "Create Keys for Hydra";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          path = config.systemd.services.hydra-init.environment.PATH;
        };
        wantedBy = [ "multi-user.target" ];
        requires = [ "hydra-init.service" ];
        after = [ "hydra-init.service" ];
        environment = builtins.removeAttrs config.systemd.services.hydra-init.environment ["PATH"];
        script = ''
          if [ ! -e ~hydra/.setup-is-complete ]; then
          # create signing keys
          /run/current-system/sw/bin/install -d -m 551 /etc/nix/hydra.wedlake.lan-1
          /run/current-system/sw/bin/nix-store --generate-binary-cache-key hydra.wedlake.lan-1 /etc/nix/hydra.wedlake.lan-1/secret /etc/nix/hydra.wedlake.lan-1/public
          /run/current-system/sw/bin/chown -R hydra:hydra /etc/nix/hydra.wedlake.lan-1
          /run/current-system/sw/bin/chmod 440 /etc/nix/hydra.wedlake.lan-1/secret
          /run/current-system/sw/bin/chmod 444 /etc/nix/hydra.wedlake.lan-1/public
          # done
          touch ~hydra/.setup-is-complete
          fi
        '';
      };
      #virtualisation.docker.enable = true;
      #virtualisation.docker.enableOnBoot = true;
      #virtualisation.docker.storageDriver = "zfs";
      virtualisation.libvirtd.enable = false;
      containers.rtorrent = {
        privateNetwork = true;
        hostAddress = "10.233.1.1";
        localAddress = "10.233.1.2";
        enableTun = true;
        config = { config, pkgs, ... }: {
          environment.systemPackages = with pkgs; [
            rtorrent
            openvpn
            tmux
            sudo
          ];
          users.users.rtorrent = {
            isNormalUser = true;
            uid = 10001;
          };
        };
      };
      users.users.cardano-node.extraGroups = [ "keys" ];
      users.users.sam = {
        isNormalUser = true;
        description = "Sam Leathers";
        uid = 1000;
        extraGroups = [ "wheel" "libvirtd" ];
        openssh.authorizedKeys.keys = shared.sam_ssh_keys;
      };
      users.users.samchat = {
        isNormalUser = true;
        description = "Sam Leathers (chat)";
        uid = 1005;
        extraGroups = [ ];
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = shared.sam_ssh_keys;
      };
      system.activationScripts.samchat-tmp =
        let bashrc = builtins.toFile "samchat-bashrc" "export TMUX_TMPDIR=/tmp";
      in "ln -svf ${bashrc} ${config.users.users.samchat.home}/.bash_profile";
      users.users.mitro = {
        isNormalUser = true;
        uid = 1001;
      };
      users.users.megan = {
        isNormalUser = true;
        uid = 1002;
      };
      users.users.nursery = {
        isNormalUser = true;
        uid = 1004;
      };
  # don't change this without reading release notes
  system.stateVersion = "17.09";
}
