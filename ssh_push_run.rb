#!/usr/bin/env ruby
# A script that takes in ARGV xor STDIN as a list of hostnames. It will execute the --execute option, then return 
# a summarized report of how the servers responded. 
# Be sure to define the exclude option to note any unique characters like time, or hostname, as this will result in 
# a large quantity of "different" results.
# I recommend jruby as a backend to execute in, but it will work in MRI.
# To use MRI, remove the references to jruby/synchronize. There are two lines to comment out. One calling the module, and the second extending the hash object allTheFiles. 
# jpark@adknowledge.com
#
require 'logger'

$log = Logger.new("#{File.dirname(__FILE__)}/log/ssh_push_run.log")
$log.level = Logger::DEBUG
$log.info "Log file created"
$logNet = Logger.new("#{File.dirname(__FILE__)}/log/ssh_push_run.net.log")
$logNet.level = Logger::DEBUG
$logNet.info "Log file created"
$logActive = Logger.new("#{File.dirname(__FILE__)}/log/ssh_push_run.active.log")
$logActive.level = Logger::DEBUG
$logActive.info "Log file created"

def do_nothing()
end

##
# :stopdoc:
# :section: Options
## 

require 'optparse'

$options = {}

optparse = OptionParser.new { |opts|
	opts.banner = "Usage: #{$0} [options]"

	$options[:executeMe] = nil
	opts.on( '-e', '--execute PARAM', "The command to execute.") { |param|
		$options[:executeMe] = param
	}

	$options[:threadCount] = 64
	opts.on( '-t', '--threads PARAM', "The number of threads. Default: 8") { |param|
		$options[:threadCount] = param
	}

	# If the below line matches data from the ssh connection, drop it 
	# This is tailored for puppet, but no harm if you're not looking at puppet output
	# Add your filters below.

	# Set the default filter
	$options[:executeDataExclude] = [
		/info: /,  # I really don't care about info posts
		/info: Applying configuration version /, # version number based on time the catalogue was generated
		/notice: Finished catalog run in /, #time metric
		/Caching catalog for/, # hostname
		/\+\+\+/, # Timestamps
		/---/, # These diff lines include timestamps
		/\[\/var\/lib\/puppet\/debug\/variables\.txt\]/, #variables in usually include hostname
		/File\[\/var\/lib\/puppet\/lib.*\]\/mode/, # mode changes are too chatty and unique
		/notice:.+content: current_value {md5}\S*, should be {md5}\S+/, #current_value tends to differ. However, --test output includes relevant data anyways.
		/-  Name = /, #bacula config replacement
		/Name = \S+-fd # This string is facter\.hostname/, #So, basically, the S+ is important so that null values do NOT match
		/err: Could not retrieve catalog.*Could not find class .*on node .*/, #These errors are node specific, but generate a final generic error at the end. 
		/Service not enabled for system profile: /,#RHEL errors
		/^\s*$/, #Empty lines

		]
	opts.on( '-x', '--exclude', 'An array of regex objects, please, like [/info:/, /notice:/]. Appends to existing puppet filter.') { |param|
		$options[:executeDataExclude].push param
	}
	opts.on( '-X', '--exclude-overwrite', 'An array of regex objects, please, like [/info:/, /notice:/]. Overwrites existing filter.') { |param|
		$options[:executeDataExclude] = param
	}

	$options[:password] = true # This way, if '-p' is not defined, then a passwd prompt is skipped
	opts.on( '-p', '--password PARAM', 'User password. use dash "-" to indicate to read from stdin') {|param|
		if /-/ =~ param
			$options[:password] = false
		else
			$options[:password] = param 
		end
	}

		$options[:loginuser] = ENV['USER']
	opts.on('--user PARAM', 'Connect as different user.') {|param|
		$options[:loginuser] = param
	}

	$options[:rootpassword] = true
	opts.on( '-P', '--rootpassword PARAM', 'Root password. use dash "-" to indicate to read from stdin') {|param|
		if /-/ =~ param 
			$options[:rootpassword] = false
		else
			$options[:rootpassword] = param 
		end
	}
	
}

# 'parse!' removes any options found in ARGV, 'parse' would not
optparse.parse!

unless $options[:executeMe]
	puts $options[:executeMe]
	print "This is garbage. Tell me what to do!!!\n"
	puts %x[#{__FILE__} --help]
	exit 1
end

def ask_for_password_on_jruby(prompt = "Enter password: ")
  raise 'Could not ask for password because there is no interactive terminal (tty)' unless $stdin.tty?
 
  require 'java'
 
  java_import 'java.lang.System'
  java_import 'java.io.Console'
 
  #$stdout.print prompt unless prompt.nil?
  $stdout.sync = true
 
  java.lang.String.new(System.console().readPassword(prompt));
  $stdout.flush
end

unless $options[:password]
	$options[:password] = ask_for_password_on_jruby "Enter password for #{$options[:loginuser]}:"
end

unless $options[:rootpassword]
	$options[:rootpassword] = ask_for_password_on_jruby "Enter password for root:"
end

# :startdoc:

def match_exclude_regex?(string) 
	match = false
	$options[:executeDataExclude].each do |regex|
		match = true if  string =~ regex
	end
	return match
end


require 'net/ssh'
require 'net/ssh/gateway'
##
# Input: Session object, the object to write to, and a custom fqdn if you want.
# Output: Console dump of the returned value when executing $executeMe
def get_the_file(session, fqdn = nil)
	fqdn = session.host unless fqdn 
	string = ""
	session.open_channel do |channel|
		channel.request_pty  do |chr, success|
			raise "request pty failed" unless success
			channel.exec( $options[:executeMe] ) do |ch, success|
				raise "command failed" unless success
				channel.on_data do |che, data|
					$log.debug "Thread #{Thread.current[:threach_num]}: #{fqdn}: Receiving data: #{data.inspect}"
					# The first 54 chars of the first line
					$counterString[fqdn] = "Thread #{Thread.current[:threach_num]}: Output: " + data.inspect.split("\n").first.chars.first(54).join 

					if data.inspect =~ /\[sudo\] password/
						channel.close
					end
					data.split("\n").each do |datasp| # Because some data units include multiple lines
						unless match_exclude_regex?(datasp) 
							$log.debug "Thread #{Thread.current[:threach_num]}: #{fqdn}: Adding #{datasp.inspect}"
							string << datasp + "\n"
						else
							$log.debug "Thread #{Thread.current[:threach_num]}: #{fqdn}: Dumping #{datasp.inspect}"
						end # unless data
					end # data split

				end #channel.on_data
			end # channel.exec
		end # channel.request_pty
	end #session.open_channel
	session.loop
	$log.info "Thread #{Thread.current[:threach_num]}: #{fqdn}: Returned output: #{string}"

	return string

end # get_the_file

#require 'java'

#java_import java.util.concurrent.Executors
#java_import java.util.concurrent.Callable
#java_import java.lang.Runtime
#java_import java.lang.System
#
#$cores = Runtime.getRuntime.availableProcessors
#executor = Executors.newFixedThreadPool($cores)
#$log.info "Detected #{$cores} cores"
#$log.info "Created executor #{executor.inspect}"

require 'jruby_threach'
require 'jruby/synchronized'
allTheFiles = {}
allTheFiles.extend(JRuby::Synchronized)

begin # Main rescue block

	##
	# A little bit cludgy, but if there are arguments left over from options matching, 
	# then assume they are hostnames to run against. 
	# Otherwise, read from STDIN
	failedNodes = []
	serverList = [] 
	puts "Enter list of servers. EOF with Ctrl+D." if $stdin.tty? 
	ARGF.each {|line|	serverList.push line.chomp }

	 
	
	$log.info "Connecting to servers:" + serverList.inspect
	puts "Connecting to #{serverList.count} servers"

	#pool = WorkQueue.new($options[:threadCount])

	#puts "Created worker pool with #{$options[:threadCount]} threads."

	class GatewayB < Net::SSH::Gateway
		attr_accessor :session
	end

	##
	# Log Active tasks

	# Mutex
	$counterString = {}
	$counterString.extend(JRuby::Synchronized)
	counter = Thread.new {
		while $counterString
			$logActive.info "##########################################"
			screen = ""
			$counterString.each { |k,v|
				$logActive.info  k.rjust(36) + ": " + v + "\n" unless v == "done"
			}
			sleep 1
		end
	}

	##
	# Kick off tasks

	serverList.threach($options[:threadCount]) do |fqdn|
		thisInstance = Thread.current
		$log.debug "Thread #{Thread.current[:threach_num]}: #{fqdn}"
			begin
			$log.info "Thread #{Thread.current[:threach_num]}: #{fqdn}: Starting work." 
			$counterString[fqdn] = "Thread #{Thread.current[:threach_num]}: Connecting via SSH"
				if fqdn =~ /dagp2/ 
					$log.info "Thread #{Thread.current[:threach_num]}: #{fqdn}: is a dagp2 server"
					gateway = GatewayB.new(
						"pda-dagp2master01.ak-networks.com", 
						'root', 
						:password => $options[:rootpassword],
						:timeout => 9, 
						:logger => $logNet, 
						:compression => true,
						:auth_methods => ['keyboard-interactive', 'password']
						)
					session = gateway.ssh(
						fqdn, 
						'root', 
						:password => $options[:rootpassword], 
						:keys => ['/root/.ssh/id_rsa'],
						:timeout => 9,
						:logger => $logNet,
						:compression => true,
						:auth_methods => ['publickey', 'keyboard-interactive', 'password']
					)
					string = get_the_file session, fqdn
				elsif fqdn =~ /pkc-gpnode/
					string = "Skipping gpnode server"
				else
					session = Net::SSH.start(
						fqdn,
						$options[:loginuser],
						:password => $options[:password],
						:timeout => 9,
						:logger => $logNet,
						:compression => true,
						:auth_methods => ['publickey', 'keyboard-interactive', 'password']
					)
					string = get_the_file session, fqdn
		
				end #if 
			rescue Net::SSH::AuthenticationFailed
				$log.warn "Thread #{Thread.current[:threach_num]}: #{fqdn}: Authentication failed." 
				$counterString[fqdn] = "ERROR AUTHFAILED"
				failedNodes.push fqdn
			rescue Errno::ETIMEDOUT
				$log.warn "Thread #{Thread.current[:threach_num]}: #{fqdn}: Connection timed out."
				$counterString[fqdn] = "ERROR TIMEOUT"
				failedNodes.push fqdn
			rescue Exception => e
				$log.error "Thread #{Thread.current[:threach_num]}: #{fqdn}: Unknown error: #{e}"
				$counterString[fqdn] = "ERROR UNKNOWN ERROR"
				failedNodes.push fqdn
			ensure
				# This is the part that needs the mutex.
				if allTheFiles[string]
					$log.debug "Thread #{Thread.current[:threach_num]}: #{fqdn}: Adding to allTheFiles: #{string}"
					allTheFiles[string].push fqdn
				else
					$log.debug "Thread #{Thread.current[:threach_num]}: #{fqdn}: New key: allTheFiles[#{string}]"
					allTheFiles[string] = [fqdn]
				end
				$counterString[fqdn] = "done"
			end	

	end #serverList.split

	$counterString = false
	counter.join
	string = "...all jobs done.\n"
	print string
	$log.info string


rescue SystemExit, Interrupt => e # Ctrl+c, for example
	puts "#{e}"
	continue
rescue StandardError => e
	puts "#{e}"
end 

$log.info "Building allTheFiles enumerable"
allTheFiles.sort_by {|k,v| v.count}.each do |data, fqdn|
	print "\nThe following #{fqdn.count} servers:\n"
	fqdn.sort().each { |v| print "#{v.split('.')[0]} " }
	print "\nreport the following:\n" 
	print "/-----------------------------------------------------------------------------------------\\\n"
	puts data
	print "\\^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^/\n"
end

puts "The following #{failedNodes.count} nodes failed to checkin:\r\n"
failedNodes.sort().each { |v| print " #{v.split('.')[0] }"  }
print "\r\n"

$log.info "Done executing!"
