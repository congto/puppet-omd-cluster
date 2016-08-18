# omd_cluster

## 2-node cluster

the following definition will create a 2-node cluster with drbd setup on /dev/sdb with ext4 on it
one site called acme will be created
webinterface is accessable via https://acme.yourdomain/acme

    class { 'omd_cluster':
        nodes => {
          host1 => {'ring0ip' => '10.0.1.183', 'ring0dev' => 'eth1', 'ring1ip' => '192.168.2.10', 'ring1dev' => 'eth2'},
          host2 => {'ring0ip' => '10.0.1.184', 'ring0dev' => 'eth1', 'ring1ip' => '192.168.2.11', 'ring1dev' => 'eth2'},
        },
        cluster_ip => '10.2.3.10',
    }



## 2-node cluster with 2 sites

the following definition will create a 2-node cluster with drbd setup on /dev/sdb with zfs (compression enabled) on it
two sites, pinky and brain, will be created
webinterface is accessable via https://acme.yourdomain/pinky and https://acme.yourdomain/brain

    class { 'omd_cluster':
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
