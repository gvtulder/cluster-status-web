require "rubygems"
require "nokogiri"
require "time"
require "json"

class Nokogiri::XML::Node
  def text_at_xpath(xpath)
    el = at_xpath(xpath)
    el ? el.text : nil
  end
end

class QstatQueue
  def self.stats(user_id_list)
    if not @cache_time or (Time.now - @cache_time) > 60 and not @refreshing_cache
      @refreshing_cache = true
      puts "Calling qstat"
      @cache = self.stats_without_cache(user_id_list)
      @cache_time = Time.now
      @refreshing_cache = false
    end
    { :timestamp=>@cache_time, :stats=>@cache }
  end

  def self.stats_without_cache(user_id_list)
    stats = Hash.new do |stats_hash, queue|
      stats_hash[queue] = Hash.new do |queue_hash, status|
        queue_hash[status] = []
      end
    end

    IO.popen(["qstat","-s","az","-u","*","-xml","-g","d","-r","-pri"]) do |io|
      doc = Nokogiri::XML(io)
      puts "Processing"
      doc.xpath("/job_info/*").each do |job_info|  # /job_info/job_info and /job_info/queue_info
        job_info.children.each do |job_list|
          fields = {}
          job_list.children.each do |child|
            fields[child.name] = child.text
          end

          job_number = fields["JB_job_number"]
          tasks = fields["tasks"]
          owner = fields["JB_owner"]
          state = fields["state"]
          state = "z" if job_list["state"] == "zombie"
          job_name = fields["JB_name"]
          running_queue = fields["queue"]
          hard_req_queue = fields["hard_req_queue"]
          start_time = fields["JAT_start_time"]
          submission_time = fields["JB_submission_time"]
          prio = fields["JAT_prio"]
 
#         job_number = job_list.text_at_xpath("JB_job_number")
#         tasks = job_list.text_at_xpath("tasks")
#         owner = job_list.text_at_xpath("JB_owner")
#         state = job_list.text_at_xpath("state")
#         state = "z" if job_list["state"] == "zombie"
#         job_name = job_list.text_at_xpath("JB_name")
#         running_queue = job_list.text_at_xpath("queue")
#         hard_req_queue = job_list.text_at_xpath("hard_req_queue")
#         start_time = job_list.text_at_xpath("JAT_start_time")
#         submission_time = job_list.text_at_xpath("JB_submission_time")
#         prio = job_list.text_at_xpath("JAT_prio")

          queue = (running_queue || hard_req_queue)
          job_id = "#{ job_number }.#{ tasks || "1" }"

          unless job_name == "QRLOGIN"
            stats[queue][state] << {
              :job_id=>job_id,
              :owner=>owner,
              :owner_id=>(user_id_list ? user_id_list.user_to_id(owner) : nil),
              :prio=>prio,
              :job_number=>job_number,
              :job_name=>job_name
            }
          end
        end
      end
    end

    puts "O"
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

    stats
  end
end

class UserIDs
  def initialize(filename)
    @filename = filename
    load_cache
  end

  def load_cache
    @cache = {}
    if File.exists?(@filename)
      @cache = (JSON.load(File.read(@filename)) rescue {})
    end
  end

  def write_cache
    File.open(@filename, "w") do |f|
      f << JSON.dump(@cache)
    end
  end

  def user_to_id(name)
    @cache[name] or (
      id = @cache.size
      @cache[name] = id
      write_cache
      id
    )
  end
end

