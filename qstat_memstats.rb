class MemoryStats
  STATS = %w{ timestamp job_number task_number owner job_name vmem_request cpu mem io iow vmem maxvmem job_project }
  #              0          1         2         3      4         5          6   7  8  9   10    11       12

  def initialize(filename)
    @filename = filename
    @last_pos = 0
    @all_job_stats = Hash.new{|h,k|h[k] = []}
    @last_job_stats = {}
    load_from_file
  end

  def stale?
    File.mtime(@filename) > @timestamp
  end

  def refresh
    if stale? and not @refreshing
      @refreshing = true
      load_from_file
      @refreshing = false
    end
    self
  end

  def [](job_id)
    JobStats.new(job_id, (@all_job_stats[job_id] || []))
  end

  def current_jobs
    latest_date = @last_job_stats.map do |job_id, job|
      job[0]
    end.max
    jobs = []
    self.each do |job_id, job|
      jobs << [job_id, job] if job[0] == latest_date
    end.sort_by do |job_id, job|
      job_id.split(".").map(&:to_i)
    end
    jobs
  end

  def each
    @last_job_stats.sort_by do |job_id, job|
      [ job[0], *job_id.split(".").map(&:to_i) ]
    end.reverse_each do |job_id, job|
      yield job_id, job
    end
  end

  private

  def load_from_file
    @timestamp = File.mtime(@filename)

    $stderr.puts "Parsing #{ @filename } from #{ @last_pos }"

    File.open(@filename) do |f|
      f.pos = @last_pos
      while line = f.gets
        cur_pos = f.pos
        if line.end_with?("\n")
          @last_pos = cur_pos
          parts = line.strip.split("\t")
          if parts[0] =~ /^[0-9]+$/
            # line with a job
            job_id = "#{ parts[1] }.#{ parts[2] }"
            @all_job_stats[job_id] << parts
            @last_job_stats[job_id] = parts
          end
        end
      end
    end

    $stderr.puts "Parsed #{ @filename } up to #{ @last_pos }"
  end

  class JobStats
    include Enumerable

    def initialize(job_id, stats)
      @job_id = job_id
      @stats = stats
    end

    def each
      @stats.reverse_each do |job|
        yield @job_id, job
      end
    end
  end
end


