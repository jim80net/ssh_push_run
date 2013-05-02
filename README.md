# ssh\_push\_run # 

JRUBY IS REQUIRED. Either use RVM or install jruby on the system.

## Usage ##
 
	jpark@jpark-mbp:~/ssh_push_run$ rake --tasks
	rake cat[arg1]       # cat["somefile"]
	rake do[arg1]        # do["something"]
	rake jruby           # Use jruby
	rake puppet_LIVE     # Perform a LIVE puppet run against every node you know about
	rake puppet_default  # Identify puppet nodes with "default" definition
	rake puppet_test     # Perform a test puppet noop run against every node you know about
	rake resolv          # audit /etc/resolv.conf
	jpark@jpark-mbp:~/vm/scripts/ssh_push_run$ 
	

Use jruby:
	rvm use jruby-head
Use bundle:
	bundle install
	bundle exec rake puppet_test 
Use time:
	time bundle exec rake cat["/etc/resolv.conf"]

