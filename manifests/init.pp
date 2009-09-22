# nagios.pp - everything nagios related
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.


# the directory containing all nagios configs:
$nagios_cfgdir = "${module_dir_path}/nagios"
module_dir{ nagios: }

# The main nagios monitor class
class nagios {
	include apache

	package {
		'nagios3':
			alias => 'nagios',
			ensure => installed;
		[ 'nagios3-common', 'nagios-plugins-basic' ]:
			ensure => installed,
			before => Package['nagios'];
	}

	service {
		'nagios3':
			alias => 'nagios',
			ensure => running,
			hasstatus => true,
			hasrestart => true,
			subscribe => File [ $nagios_cfgdir ]
	}

	file {
		# prepare a place for a password for the nagiosadmin
		"/etc/nagios3/htpasswd.users":
			ensure => present,
			mode => 0640, owner => root, group => www-data;
		# disable default debian configurations
		[ "/etc/nagios3/conf.d/localhost_nagios2.cfg",
		  "/etc/nagios3/conf.d/extinfo_nagios2.cfg",
		  "/etc/nagios3/conf.d/services_nagios2.cfg" ]:
			ensure => absent,
			notify => Service[nagios];
		"/etc/nagios3/conf.d/hostgroups_nagios2.cfg":
			source => "puppet://$servername/nagios/hostgroups_nagios.cfg",
			mode => 0644, owner => root, group => www-data,
			notify => Service[nagios];
		# permit external commands from the CGI
		"/var/lib/nagios3":
			ensure => directory, mode => 751,
			owner => nagios, group => nagios,
			notify => Service[nagios];
		"/var/lib/nagios3/rw":
			ensure => directory, mode => 2710,
			owner => nagios, group => www-data,
			notify => Service[nagios];
		"/usr/local/bin":
			source => "puppet:///nagios/bin/",
			recurse => true,
			mode => 0755, owner => root, group => 0;
	}

	# TODO: these are not very robust!
	replace {
		# enable external commands from the CGI
		enable_extcommands:
			file => "/etc/nagios3/nagios.cfg",
			pattern => "check_external_commands=0",
			replacement => "check_external_commands=1",
			notify => Service[nagios];
		# put a cap on service checks
		cap_service_checks:
			file => "/etc/nagios3/nagios.cfg",
			pattern => "max_concurrent_checks=0",
			replacement => "max_concurrent_checks=30",
			notify => Service[nagios];
	}

	line { include_cfgdir:
		file => "/etc/nagios3/nagios.cfg",
		line => "cfg_dir=$nagios_cfgdir",
		notify => Service[nagios],
	}

	munin::remoteplugin {
		nagios_hosts: source => 'puppet:///nagios/bin/nagios_hosts';
		nagios_svc: source => 'puppet:///nagios/bin/nagios_svc';
		nagios_perf_hosts: source => 'puppet:///nagios/bin/nagios_perf_';
		nagios_perf_svc: source => 'puppet:///nagios/bin/nagios_perf_';
	}

	file { "/etc/munin/plugin-conf.d/nagios":
		content => "[nagios_*]\nuser root\n",
		mode => 0644, owner => root, group => root,
		notify => Service[munin-node]
	}

	# import the various definitions
	File <<| tag == 'nagios' |>>

	define command($command_line) {
		file { "$nagios_cfgdir/${name}_command.cfg":
				ensure => present, content => template( "nagios/command.erb" ),
				mode => 644, owner => root, group => root,
				notify => Service[nagios],
		}
	}

	nagios::command {
		# from ssh.pp
		ssh_port:
			command_line => '/usr/lib/nagios/plugins/check_ssh -p $ARG1$ $HOSTADDRESS$';
		# from apache2.pp
		http_port:
			command_line => '/usr/lib/nagios/plugins/check_http -p $ARG1$ -H $HOSTADDRESS$ -I $HOSTADDRESS$';
		# from bind.pp
		nameserver: command_line => '/usr/lib/nagios/plugins/check_dns -H www.edv-bus.at -s $HOSTADDRESS$';
		# TODO: debug this, produces copious false positives:
		# check_dig2: command_line => '/usr/lib/nagios/plugins/check_dig -H $HOSTADDRESS$ -l $ARG1$ --record_type=$ARG2$ --expected_address=$ARG3$ --warning=2.0 --critical=4.0';
		check_dig2: command_line => '/usr/lib/nagios/plugins/check_dig -H $HOSTADDRESS$ -l $ARG1$ --record_type=$ARG2$';
		check_dig3: command_line => '/usr/lib/nagios/plugins/check_dig -H $ARG3$ -l $ARG1$ --record_type=$ARG2$';
	}

	define host($ip = $fqdn, $short_alias = $fqdn) {
		@@file {
			"$nagios_cfgdir/${name}_host.cfg":
				ensure => present, content => template( "nagios/host.erb" ),
				mode => 644, owner => root, group => root,
				tag => 'nagios'
		}
	}

	define service($check_command = '', 
		$nagios_host_name = $fqdn, $nagios_description = '')
	{
		# this is required to pass nagios' internal checks:
		# every service needs to have a defined host
		include nagios::target
		$real_check_command = $check_command ? {
			'' => $name,
			default => $check_command
		}
		$real_nagios_description = $nagios_description ? {
			'' => $name,
			default => $nagios_description
		}
		@@file {
			"$nagios_cfgdir/${nagios_host_name}_${name}_service.cfg":
				ensure => present, content => template( "nagios/service.erb" ),
				mode => 644, owner => root, group => root,
				tag => 'nagios'
		}
	}

	define extra_host($ip = $fqdn, $short_alias = $fqdn, $parent = "none") {
		$nagios_parent = $parent
		file {
			"$nagios_cfgdir/${name}_host.cfg":
				ensure => present, content => template( "nagios/host.erb" ),
				mode => 644, owner => root, group => root,
				notify => Service[nagios],
		}
	}
	
	# include this class in every host that should be monitored by nagios
	class target {
		nagios::host { $fqdn: }
		debug ( "$fqdn has $nagios_parent as parent" )
	}

}

class nagios2 {
	err("Legacy class 'nagios2' included, use 'nagios' instead.")
	include nagios
}

