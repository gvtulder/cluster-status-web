require "rubygems"
require "nokogiri"
require "time"

class Nokogiri::XML::Node
  def text_at_xpath(xpath)
    el = at_xpath(xpath)
    el ? el.text : nil
  end
end

USAGES = %w{ cpu mem io iow vmem maxvmem }
def print_job_stats
  $stderr.puts Time.now

  job_ids = []
  $stderr.print "Asking qstat for job IDs... "
  IO.popen([ "qstat", "-s", "r", "-u", "*", "-xml" ]) do |f|
    doc = Nokogiri::XML(f)
    doc.xpath("//job_list").each do |job_list|
      job_number = job_list.text_at_xpath("JB_job_number")
      tasks = job_list.text_at_xpath("tasks")
      job_ids << job_number
    end
  end
  job_ids = job_ids.uniq
  $stderr.puts "done. Found #{ job_ids.size } job#{ "s" unless job_ids.size==1 }."

  $stderr.print "Requesting detailed memory information... "
  jobs = {}
  IO.popen([ "qstat", "-j", job_ids.join(","), "-xml" ]) do |f|
    doc = Nokogiri::XML(f)
    doc.xpath("//djob_info/element").each do |djob_info|
      job_number = djob_info.text_at_xpath("JB_job_number")
      job_data = {}
      job_data = {
        "JB_owner" => djob_info.text_at_xpath("JB_owner"),
        "JB_job_name" => djob_info.text_at_xpath("JB_job_name").gsub(/\s+/, ""),
        "vmem_request" => djob_info.text_at_xpath("JB_hard_resource_list/qstat_l_requests[CE_name='h_vmem']/CE_doubleval")
      }
      tasks = {}
      djob_info.xpath("JB_ja_tasks/ulong_sublist").each do |task|
        task_number = task.text_at_xpath("JAT_task_number")
        uas = {}
        task.xpath("JAT_scaled_usage_list/scaled").each do |ua|
          ua_name = ua.text_at_xpath("UA_name")
          ua_value = ua.text_at_xpath("UA_value")
          uas[ua_name] = ua_value
        end
        tasks[task_number] = uas
      end
      job_data["tasks"] = tasks
      jobs[job_number] = job_data
    end
  end
  n_tasks = jobs.values.inject(0){|s,j|s+j["tasks"].size}
  $stderr.puts "done. Found #{ n_tasks } task#{ "s" unless n_tasks==1 }."

  puts [ "timestamp", "job_number", "task_number", "owner", "job_name", "vmem_request", *USAGES ].join("\t")
  jobs.each do |job_number, job_data|
    job_data["tasks"].each do |task_number, task_data|
      puts [Time.now.to_i,
            job_number,
            task_number,
            job_data["JB_owner"],
            job_data["JB_job_name"],
            job_data["vmem_request"],
            *USAGES.map{|ua|task_data[ua]}].join("\t")
    end
  end

  $stderr.puts
  
  $stdout.flush
end

10.times do
  print_job_stats
  sleep 120
end
print_job_stats


