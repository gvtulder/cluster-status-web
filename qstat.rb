require "rubygems"
require "nokogiri"
require "time"

class Nokogiri::XML::Node
  def text_at_xpath(xpath)
    el = at_xpath(xpath)
    el ? el.text : nil
  end
end

class Qstat
  # list of job ids with state "r"
  def self.running_job_ids
    job_ids("r")
  end

  # list of job ids for jobs with the given state
  def self.job_ids(state="r")
    job_ids = []
    IO.popen([ "qstat", "-s", state, "-u", "*", "-xml" ]) do |f|
      Nokogiri::XML(f).xpath("/job_info/queue_info/job_list/JB_job_number").each do |job_number|
        job_ids << job_number.text
      end
    end
    job_ids = job_ids.uniq
  end

  # hash of job_id => job details
  def self.job_details(job_ids)
    jobs = {}
    xml_str = IO.popen([ "qstat", "-j", job_ids.join(","), "-xml" ]) do |f|
      f.read
    end

    # qstat may produce invalid XML: for jobs in error state
    # it adds elements like this
    #
    # <JATASK:  631165.>
    #   <JAT_status>128</JAT_status>
    #   <JAT_task_number>1</JAT_task_number>
    # </JATASK:  631165.>

    xml_str = xml_str.gsub(/<JATASK:\s*[.0-9]+>.+?<\/JATASK:\s*[.0-9]+>/m, "")

    doc = Nokogiri::XML(xml_str, nil, nil, Nokogiri::XML::ParseOptions::STRICT)
    doc.xpath("/detailed_job_info/djob_info/element").each do |element|
      # collect info about the job
      job_data = {}
      element.children.each do |child|
        case child.name
        when "JB_job_number", "JB_owner", "JB_job_name", "JB_project", "JB_submission_time", "JB_start_time"
          job_data[child.name] = child.text.delete(" \t\r\n")
        when "JB_hard_resource_list"
          job_data["vmem_request"] = child.text_at_xpath("*[CE_name='h_vmem']/CE_doubleval")
        when "JB_pe_range"
          job_data["nslots"] = child.text_at_xpath("ranges/RN_max").to_i
        end
      end
      job_number = job_data["JB_job_number"]

      # collect info about tasks in this job
      tasks = {}
      element.xpath("JB_ja_tasks/ulong_sublist").each do |task|
        task_number = task.text_at_xpath("JAT_task_number")
        uas = {}
        # task resource usage
        task.xpath("JAT_scaled_usage_list/scaled").each do |ua|
          ua_name, ua_value = nil, nil
          ua.children.each do |ua_child|
            case ua_child.name
            when "UA_name"
              ua_name = ua_child.text
            when "UA_value"
              ua_value = ua_child.text
            end
          end
          uas[ua_name] = ua_value
        end
        tasks[task_number] = uas
      end
      job_data["tasks"] = tasks

      # add to the list
      job_ids << job_number
      jobs[job_number] = job_data
    end

    jobs
  end

  # hash[queue][state] = [... jobs ...]
  def self.jobs_per_queue(user_id_list=nil, status="az")
    stats = Hash.new do |stats_hash, queue|
      stats_hash[queue] = Hash.new do |queue_hash, status|
        queue_hash[status] = []
      end
    end

    doc = IO.popen(["qstat","-s",status,"-u","*","-xml","-g","d","-r","-pri"]) do |io|
      Nokogiri::XML(io)
    end

    doc.xpath("/job_info/*").each do |job_info|  # /job_info/job_info and /job_info/queue_info
      job_info.children.each do |job_list|
        if job_list.name == "job_list"
          fields = {}
          job_list.children.each do |child|
            fields[child.name] = child.text
          end

          job_number = fields["JB_job_number"]
          tasks = fields["tasks"]
          owner = fields["JB_owner"]
          state = fields["state"]
          state = "z" if job_list["state"] == "zombie"
          # move hold+running and deleted+running to the running group
          state = "r" if state =~ /r/
          job_name = fields["JB_name"]
          queue_name = fields["queue_name"].to_s[/^([a-z]+)@node/, 1]
          running_queue = fields["queue"]
          hard_req_queue = fields["hard_req_queue"]
          start_time = fields["JAT_start_time"]
          submission_time = fields["JB_submission_time"]
          prio = fields["JAT_prio"]
   
          queue = (queue_name || running_queue || hard_req_queue)
          if tasks
            job_id_display = "#{ job_number }.#{ tasks }"
          else
            job_id_display = "#{ job_number }"
          end
          job_id = "#{ job_number }.#{ tasks || "1" }"

          unless job_name == "QRLOGIN"
            stats[queue][state] << {
              :job_id=>job_id,
              :job_id_display=>job_id_display,
              :owner=>owner,
              :owner_id=>(user_id_list ? user_id_list.user_to_id(owner) : nil),
              :prio=>prio,
              :job_number=>job_number,
              :job_name=>job_name,
              :submission_time=>submission_time,
              :start_time=>start_time
            }
          end
        end
      end
    end

    stats.each_value do |queue_h|
      queue_h.each do |status, status_h|
        if status == "z"
          status_h.sort_by! do |job|
            job[:owner]
          end
        else
          status_h.sort_by! do |job|
            job[:prio].to_f
          end
        end
      end
    end
  end

  QUEUE_ORDER = %w{ hour day week month }
  RESOURCE_ORDER = %w{ slots h_vmem }

  def self.resources_per_host
    doc = IO.popen(["qhost","-F","-xml"]) do |io|
      Nokogiri::XML(io)
    end

    hosts = {}

    doc.xpath("/qhost/host").each do |host_el|
      host_data = { :name=> host_el["name"], :hostvalues=>{}, :resourcevalues=>{} }
      hosts[host_data[:name]] = host_data

      host_el.xpath("hostvalue").each do |el|
        host_data[:hostvalues][el["name"]] = el.text
      end
      host_el.xpath("resourcevalue").each do |el|
        host_data[:resourcevalues][el["name"]] = el.text
      end
    end

    hosts
  end

  def self.quota
    doc = IO.popen(["qquota","-u","*","-xml"]) do |io|
      Nokogiri::XML(io)
    end
    # there might be a bug in qquota: it declares an xmlns pointing to the xsd
    doc.remove_namespaces!

    rules = doc.xpath("/qquota_result/qquota_rule").map do |el|
      limits = el.xpath("limit").map do |limit_el|
        { :resource=>limit_el["resource"], :limit=>limit_el["limit"], :value=>limit_el["value"] }
      end
      queues = el.xpath("queues").map(&:text).sort_by { |q| QUEUE_ORDER.index(q) }
      users = el.xpath("users").map(&:text) - ["*"]

      if queues == ["day","week","month"] or queues == QUEUE_ORDER
        queues = []
      end

      { :limits=>limits, :queues=>queues, :users=>users }
    end

    rules = rules.sort_by do |rule|
      [ rule[:users].empty? ? "AAAAAAAAAAAAAAAA" : rule[:users].to_s,
        rule[:limits].map{ |l| RESOURCE_ORDER.index(l[:resource]) },
        rule[:queues].size,
        rule[:queues].map{ |q| QUEUE_ORDER.index(q) or 99 },
      ]
    end
  end
end

