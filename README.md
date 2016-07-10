# puppet-omd-cluster

    class { 'omd-cluster':
        nodes => {
          host1 => {'ring0ip' => '10.0.1.183', 'ring0dev' => 'eth1', 'ring1ip' => '192.168.2.10', 'ring1dev' => 'eth2'},
          host2 => {'ring0ip' => '10.0.1.184', 'ring0dev' => 'eth1', 'ring1ip' => '192.168.2.11', 'ring1dev' => 'eth2'},
        },
        cluster_ping_hostlist => '10.1.2.3 10.2.3.4',
        cluster_sites => {
          pinky => {'id' => '500', 'port' => '5000'},
          brain => {'id' => '501', 'port' => '5001'},
        },
        cluster_name => "acme",
        cluster_ip => '10.2.3.10',
        omd_filesystem => 'zfs',
    }
