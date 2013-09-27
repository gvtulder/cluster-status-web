require "rubygems"
require "time"
require "sqlite3"

require "./qstat"
require "./history"


# collect statistics of currently running jobs,
# write statistics to database
def collect_job_stats(history)
  $stderr.puts Time.now

  $stderr.print "Asking qstat for job IDs... "
  job_ids = Qstat.running_job_ids
  $stderr.puts "done. Found #{ job_ids.size } job#{ "s" unless job_ids.size==1 }."

  $stderr.print "Requesting detailed memory information... "
  jobs = Qstat.job_details(job_ids)
  n_tasks = jobs.values.inject(0){|s,j|s+j["tasks"].size}
  $stderr.puts "done. Found #{ n_tasks } task#{ "s" unless n_tasks==1 }."

  history.store_job_stats(jobs)
  $stderr.puts
  
  $stdout.flush
end

loop do
  History.today do |history|
    # collect and store stats
    collect_job_stats(history)
  end

  # gzip-compress old databases
  History.archive!

  sleep 120
end

