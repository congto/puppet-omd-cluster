class omd_cluster (
    $nodes = undef,
    $cluster_sites = {"acme" => {'id' => '500', 'port' => '5000'}},
    $multisite_sites = {},
    $cluster_name = "acme",
    $cluster_ip = undef,
    $cluster_quorum = "sdb",
    $cluster_uid = "999",
    $cluster_ping_hostlist = "8.8.8.8",
    $omdversion = "omd-1.30",
    $omd_filesystem = "ext4",
) {

    $cluster_sitenames = keys($cluster_sites)

    define create::sites($sites) {
        $site = $name
        $id = $sites[$name]['id']
        $port = $sites[$name]['port']

        exec { "/bin/init-omd.sh $site $id $port":
            creates => "/etc/init-omd.$site",
            require => File['/bin/init-omd.sh'],
        }
    }
    define create::sitePrimitive($sites) {
        $site = $name

        exec { "/usr/sbin/crm configure primitive pri_omd_$site ocf:omd:OMD op monitor interval='10s' timeout='20s' op start interval='0s' timeout='90s' op stop interval='0s' timeout='100s' params site='$site'":
            unless => "/usr/sbin/crm configure show | /bin/grep -q 'primitive pri_omd_$site'",
        } ->
        exec { "/usr/sbin/crm configure colocation col_omd_${site}_follows_drbd inf: pri_omd_$site ms_drbd_omd:Master":
            unless => "/usr/sbin/crm configure show | /bin/grep -q 'colocation col_omd_${site}_follows_drbd'",
        } ->
        exec { "/usr/sbin/crm configure order ord_omd_before_$site inf: group_omd:start pri_omd_$site:start":
            unless => "/usr/sbin/crm configure show | /bin/grep -q 'order ord_omd_before_${site}'",
        }
    }

    # add needed repos
    yumrepo { "elrepo":
        baseurl => 'http://elrepo.org/linux/elrepo/el6/$basearch/',
        descr => "elrepo",
        enabled => 1,
        gpgcheck => 0,
    }
    yumrepo { "crmsh":
        baseurl => 'http://download.opensuse.org/repositories/network:/ha-clustering:/Stable/CentOS_CentOS-6/',
        descr => "Stable High Availability/Clustering packages (CentOS_CentOS-6)",
        enabled => 1,
        gpgcheck => 1,
        gpgkey => "http://download.opensuse.org/repositories/network:/ha-clustering:/Stable/CentOS_CentOS-6/repodata/repomd.xml.key",
        includepkgs => "crmsh,pssh,python-parallax,crmsh-scripts",
    }
    yumrepo { "labs.consol.de":
        baseurl => 'https://labs.consol.de/repo/stable/rhel6/$basearch/',
        descr => "omdistro",
        enabled => 1,
        gpgcheck => 0,
        gpgkey => "https://labs.consol.de/repo/stable/RPM-GPG-KEY",
    }
    if ( $omd_filesystem == 'zfs' ) {
        yumrepo { "zfs":
            baseurl => 'http://archive.zfsonlinux.org/epel/6/$basearch/',
            descr => 'ZFS on Linux for EL 6',
            enabled => 1,
            metadata_expire => '7d',
            gpgcheck => 0,
            gpgkey => 'http://keys.gnupg.net:11371/pks/lookup?search=0xF14AB620&op=get',
        }
        package { "zfs":
            ensure => "installed",
            require => Yumrepo['zfs'],
        }
        $primitive_definition = "ocf:heartbeat:ZFS"
        $primitive_params = "params pool='tank' op start timeout='90' op stop timeout='90'"
        file { "/usr/lib/ocf/resource.d/heartbeat/ZFS":
            source => "puppet:///modules/omd_cluster/ZFS.ocf",
            mode => '0755',
            owner => root,
            group => root,
            require => Package['pacemaker'],
        }->
        file { "/usr/lib/ocf/lib/heartbeat/helpers":
            ensure => "directory"
        } ->
        file { "/usr/lib/ocf/lib/heartbeat/helpers/zfs-helper":
            source => "puppet:///modules/omd_cluster/zfs-helper",
            mode => '0755',
            owner => root,
            group => root,
            require => Package['pacemaker'],
        } ->
        file { "/bin/stmf-ha":
            source => "puppet:///modules/omd_cluster/stmf-ha",
            mode => '0555',
            owner => root,
            group => root,
        }
    } elsif ( $omd_filesystem == 'ext4') {
        $primitive_definition = "ocf:heartbeat:Filesystem op monitor interval='5s' timeout='10s'"
        $primitive_params = "device='/dev/drbd0' fstype='ext4' directory='/mnt/omddata/' meta target-role='Started'"
    }
    file { "/bin/nodeusage":
        source => "puppet:///modules/omd_cluster/nodeusage",
        mode => '0555',
        owner => root,
        group => root,
    }
    file { "/etc/hosts.local":
        mode => '0644',
        owner => root,
        group => root,
        content => template('omd_cluster/hosts.local.erb'),
    }
    exec {'disable_selinux_config':
        command => '/bin/sed -i "s/.*SELINUX=enforcing.*/SELINUX=disabled/" /etc/selinux/config',
        unless  => '/bin/grep "SELINUX=disabled" /etc/selinux/config'
    }

    # install eveything whats needed
    package { ["drbd83-utils","kmod-drbd83","corosync","pacemaker","crmsh","httpd","mod_ssl","libdbi","$omdversion"]:
        ensure => "installed",
        require => Yumrepo["elrepo","crmsh","labs.consol.de"],
    } ->
    # stop omd ... will be handled by corosync
    service { "omd":
        enable => false,
        require => Package["$omdversion"]
    }

    # add network config
    network::if::static { $nodes[$hostname]['ring0dev']:
        ensure    => 'up',
        ipaddress => $nodes[$hostname]['ring0ip'],
        netmask   => '255.255.255.0',
    } ->
    network::if::static { $nodes[$hostname]['ring1dev']:
        ensure    => 'up',
        ipaddress => $nodes[$hostname]['ring1ip'],
        netmask   => '255.255.255.0',
    } ->
    firewall { "051 corosync ring0":
        proto => udp,
        dport => 5410,
        action  => accept
    } ->
    firewall { "051 corosync ring1":
        proto => udp,
        dport => 5415,
        action  => accept
    } ->
    firewall { "051 pacemaker":
        proto => udp,
        dport => [5404,5405],
        action  => accept
    } ->
    firewall { "051 drbd":
        proto => tcp,
        dport => 7788,
        action  => accept
    } ->
    # create a blockdevice and run corosync config
    exec { "/sbin/modprobe drbd":
        unless => "/sbin/lsmod | /bin/grep drbd",
        require => [ Package["drbd83-utils"], Package["kmod-drbd83"] ],
    } ->
    exec { "/sbin/pvcreate /dev/$cluster_quorum && /sbin/vgcreate vg_omd_data /dev/$cluster_quorum && /sbin/lvcreate -L 1G -n lv_omd_quorum vg_omd_data":
        unless => "/sbin/lvs | /bin/grep lv_omd_quorum"
    } ->
    file { "/etc/default/corosync":
        mode => '0644',
        owner => root,
        group => root,
        content => "START=yes",
    } ->
    file { "/etc/corosync/corosync.conf":
        mode => '0644',
        owner => root,
        group => root,
        content => template('omd_cluster/corosync.conf.erb'),
        notify  => Service["corosync"],
    } ->
    file { "/etc/logrotate.d/corosync":
        mode => '0644',
        owner => root,
        group => root,
        source => "puppet:///modules/omd_cluster/corosync",
        notify  => Service["corosync"],
    } ->
    file { "/etc/drbd.d/romd.res":
        mode => '0644',
        owner => root,
        group => root,
        content => template('omd_cluster/romd-drbd.res.erb'),
        notify => Service['drbd'],
    } ->
    service { 'corosync':
      ensure => running,
      enable => true,
    } ->
    service { 'drbd':
      ensure => running,
      enable => true,
    } ->
    service { 'pacemaker':
        ensure => running,
        enable => true,
    } ->
    exec { "/usr/sbin/crm configure property stonith-enabled='false'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q stonith-enabled='false'"
    } ->
    exec { "/usr/sbin/crm configure property no-quorum-policy='ignore'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q no-quorum-policy='ignore'"
    } ->
    exec { "/usr/sbin/crm configure rsc_defaults resource-stickiness='1'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q resource-stickiness='1'"
    } ->
    exec { "/usr/sbin/crm --force configure primitive pri_ping ocf:pacemaker:ping params dampen='20s' multiplier='1000' host_list='$cluster_ping_hostlist' op monitor interval='5s'":
        unless => "/usr/sbin/crm configure show | /bin/grep 'params dampen=20s multiplier=1000 host_list=' | /bin/grep -q '$cluster_ping_hostlist'"
    } ->

    file { "/bin/init-drbd.sh":
        content => template('omd_cluster/init-drbd.sh.erb'),
        mode => '0755',
        owner => root,
        group => root,
    } ->
    file { "/bin/init-omd.sh":
        content => template('omd_cluster/init-omd.sh.erb'),
        mode => '0755',
        owner => root,
        group => root,
    }

    exec { "/sbin/drbdadm create-md romd && /sbin/drbdadm up romd && /bin/init-drbd.sh":
        creates => "/opt/omd/init-drbd",
        require => File['/bin/init-drbd.sh'],
    } ->
    exec { "/usr/sbin/crm configure primitive pri_drbd_omd ocf:linbit:drbd params drbd_resource='romd' op monitor interval='5'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q 'pri_drbd_omd ocf:linbit:drbd'",
    } ->
    exec { "/usr/sbin/crm configure ms ms_drbd_omd pri_drbd_omd meta master-max='1' master-node-max='1' clone-max='2' clone-node-max='1' notify='true'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q 'ms_drbd_omd pri_drbd_omd'",
    } ->
    file { "/mnt/omddata":
        ensure => "directory",
    } ->
    exec { "/usr/sbin/crm configure primitive pri_fs_omd $primitive_definition  params $primitive_params":
        unless => "/usr/sbin/crm configure show | /bin/grep -q 'pri_fs_omd'",
    }->
    exec { "/usr/sbin/crm configure primitive pri_nagiosIP ocf:heartbeat:IPaddr2 op monitor interval='5s' timeout='10s' params ip='$cluster_ip' cidr_netmask='24' iflabel='NagiosIP'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q 'pri_nagiosIP'",
    } ->
    exec { "/usr/sbin/crm configure primitive pri_IPsrcaddr ocf:heartbeat:IPsrcaddr op monitor interval='5s' timeout='10s' params ipaddress='$cluster_ip'":
        unless => "/usr/sbin/crm configure show | /bin/grep -q 'pri_IPsrcaddr'",
    } ->
    file { "/etc/httpd/conf.d/001status.conf":
        content => "NameVirtualHost *:80
<VirtualHost _default_:80>
  ServerAdmin nagios@$domain
  <Location /server-status>
      SetHandler server-status
      Order deny,allow
      Allow from all
  </Location>
</VirtualHost>",
    } ->
    exec { "/usr/sbin/crm configure primitive pri_apache ocf:heartbeat:apache op monitor interval='5' timeout='20' op start interval='0' timeout='60' op stop interval='0' timeout='60' params configfile='/etc/httpd/conf/httpd.conf' testregex='body' statusurl='http://localhost/server-status'":
      unless => "/usr/sbin/crm configure show | /bin/grep -q 'primitive pri_apache'",
    }

    create::sites { $cluster_sitenames:
        sites => $cluster_sites
    } ->
    file { "/usr/lib/ocf/resource.d/omd":
        ensure => "directory"
    } ->
    file { "/usr/lib/ocf/resource.d/omd/OMD":
        source => "puppet:///modules/omd_cluster/OMD.ocf",
        mode => '0755',
        owner => root,
        group => root,
    } ->
    file { "/root/omd-ocf.te":
        source => "puppet:///modules/omd_cluster/omd-ocf.te",
    } ->
    exec { "/bin/echo 'kernel.sem = 512 32000 100 512' >> /etc/sysctl.conf && /sbin/sysctl -p":
        unless => "/bin/grep -q 'kernel.sem = 512 32000 100 512' /etc/sysctl.conf",
    } ->
#    exec { "/usr/bin/checkmodule -M -m -o /root/omd-ocf.mod /root/omd-ocf.te && /usr/bin/semodule_package -m /root/omd-ocf.mod -o /root/omd-ocf.pp && /usr/sbin/semodule -i /root/omd-ocf.pp":
#        creates => "/etc/selinux/targeted/modules/active/modules/omd-ocf.pp",
#    } ->
    exec { "/usr/sbin/setenforce 0":
        unless => "/usr/sbin/sestatus | /bin/egrep -q '(Current mode:.*permissive|SELinux.*disabled)'";
    } ->
#    exec { "/usr/sbin/crm configure primitive pri_omd_$cluster_name ocf:omd:OMD op monitor interval='10s' timeout='20s' op start interval='0s' timeout='90s' op stop interval='0s' timeout='100s' params site='$cluster_name'":
#        unless => "/usr/sbin/crm configure show | /bin/grep -q 'primitive pri_omd_$cluster_name'",
#    } ->
    create::sitePrimitive { $cluster_sitenames:
        sites => $cluster_sites
    } ->
    exec { '/usr/sbin/crm configure location loc_drbdmaster_ping ms_drbd_omd rule \$id="loc_drbdmaster_ping-rule" \$role="Master" pingd: defined pingd':
        unless => "/usr/sbin/crm configure show | /bin/grep -q 'location loc_drbdmaster_ping'",
    } ->
    exec { "/usr/sbin/crm configure group group_omd pri_fs_omd pri_apache pri_nagiosIP pri_IPsrcaddr":
      unless => "/usr/sbin/crm configure show | /bin/grep -q 'group group_omd'",
    } ->
    exec { "/usr/sbin/crm configure colocation col_omd_follows_drbd inf: group_omd ms_drbd_omd:Master":
      unless => "/usr/sbin/crm configure show | /bin/grep -q 'colocation col_omd_follows_drbd'",
    } ->
    exec { "/usr/sbin/crm configure order ord_drbd_before_omd inf: ms_drbd_omd:promote group_omd:start":
      unless => "/usr/sbin/crm configure show | /bin/grep -q 'order ord_drbd_before_omd'",
    } ->
#    create::siteSettings { $cluster_sitenames:
#        sites => $cluster_sites
#    } ->
#    exec { "/usr/sbin/crm configure colocation col_omd_${cluster_name}_follows_drbd inf: pri_omd_$cluster_name ms_drbd_omd:Master":
#      unless => "/usr/sbin/crm configure show | /bin/grep -q 'colocation col_omd_${cluster_name}_follows_drbd'",
#    } ->
#    exec { "/usr/sbin/crm configure order ord_omd_before_$cluster_name inf: group_omd:start pri_omd_$cluster_name:start":
#      unless => "/usr/sbin/crm configure show | /bin/grep -q 'order ord_omd_before_${cluster_name}'",
#    } ->
    exec { '/usr/bin/openssl req -x509 -newkey rsa:2048 -keyout /etc/ssl-omd.key -out /etc/ssl-omd.pem -nodes -subj "/CN=localhost"':
        unless => '/usr/bin/test -e /etc/ssl-omd.key',
    }

    file { "/etc/httpd/conf.d/omd.conf":
        mode => '0644',
        owner => root,
        group => root,
        content => template('omd_cluster/reverseproxy.erb'),
        require => Package["httpd"],
    }
    file { "/var/www/html/index.html":
        mode => '0644',
        owner => root,
        group => root,
        content => template('omd_cluster/index.html.erb'),
        require => Package["httpd"],
    }
    # handy files for simple administration
    file { "/etc/profile.d/omd_cluster.sh":
        mode => '0600',
        owner => root,
        group => root,
        source => "puppet:///modules/omd_cluster/omd_cluster.sh.profile",
    }

}
