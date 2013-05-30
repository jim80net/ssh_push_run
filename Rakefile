##
# This method was adapted from: 
# http://stackoverflow.com/questions/1154846/continuously-read-from-stdout-of-external-process-in-ruby
def shell_spawn(cmd)
	require 'pty'
	begin
		PTY.spawn (cmd) do |stdin, stdout, pid|
			begin
				stdin.each { |line| print line }
			rescue Errno::EIO
			end
		end # PTY.spawn
	rescue PTY::ChildExited
		puts "The child process exited."
	end
end # def shell_spawn

desc "Use jruby"
task :jruby do
	a = IO.popen("which jruby")
	a.close
	unless $? == 0
		puts "Error. No jruby found."
		exit 1
	end
end

task :password do
	raise 'Could not ask for password because there is no interactive terminal (tty)' unless $stdin.tty?
	require 'java'
 
	java_import 'java.lang.System'
	java_import 'java.io.Console'
 
	#$stdout.print prompt unless prompt.nil?
	$stdout.sync = true

	prompt = "Enter username: "
	$username = java.lang.String.new(System.console().readPassword(prompt));

	prompt = "Enter #{$username} password:  "
	$password = java.lang.String.new(System.console().readPassword(prompt));
end
	

task :do => :password # Every task needs passwords
desc 'do["something"]'
task :do, :arg1 do |t, args|
	puts "Doing #{args}"
	args.each { |k,v | 
		shell_spawn %Q[bash lists/get_sql.sh | jruby ssh_push_run.rb --user="#{$username}" --password="#{$password}" --execute "if /usr/lib/nagios/plugins/check_load -r -c 200 -w 200 &>/dev/null; then #{v}; else echo LOAD TOO HIGH; fi"]
	}
end

desc "Perform a test puppet noop run against every node you know about"
task :puppet_test do
	Rake::Task[:do].invoke("sudo puppet agent --test --verbose --environment test --server pkc-itconfig.ak-networks.com --noop")
end

desc "Perform a LIVE puppet run against every node you know about"
task :puppet_LIVE do
	Rake::Task[:do].invoke("sudo puppet agent --test --verbose --server pkc-itconfig.ak-networks.com --no-noop")
end

desc "Perform a test puppet noop run against every node you know about. No diffs."
task :puppet_test_nodiff do
	Rake::Task[:do].invoke("sudo puppet agent --verbose --onetime --ignorecache --no-daemonize --no-splay --no-show_diff --environment test --server pkc-itconfig.ak-networks.com --noop")
end

desc "Perform a LIVE puppet run against every node you know about. No diffs"
task :puppet_LIVE_nodiff do
	Rake::Task[:do].invoke("sudo puppet agent --verbose --onetime --irnorecache --no-daemonize --no-sply --no-show_diff --server pkc-itconfig.ak-networks.com --no-noop")
end

desc "audit /etc/resolv.conf "
task :resolv do
	Rake::Task[:do].invoke("cat /etc/resolv.conf | sed -e '/^\S*$/d' -e '/\S*#/d'")
end

desc "Identify puppet nodes with \"default\" definition"
task :puppet_default do
	Rake::Task[:do].invoke("cat /var/lib/puppet/classes.txt | grep default")
end

desc 'Upgrade OMSA to 7.2'
task :omsa72 do
	Rake::Task[:do].invoke("sudo /home/jpark/scripts/sles_repo_reset/sles_repo_reset.sh && sudo /home/jpark/scripts/upgrade_omsa/upgrade_omsa.sh")
end

desc 'cat["somefile"]'
task :cat, :arg1 do |t, args|
	puts "Auditing #{args}"
	args.each { |k,v | 
		Rake::Task[:do].invoke( "sudo cat #{v} | sed -e '/^\S*$/d' -e '/\S*#/d'")
	}
end


# Every task needs jruby 
#Rake.application.tasks.each do |taskname|
	#task taskname => :jruby unless "#{taskname}" == "jruby"
	#p "#{taskname}".to_sym
#end
