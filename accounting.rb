require "rubygems"
require "elif"
require "rbtree"
require "set"
require "json"

require "./qstat"
require "./user_ids"

outfile = ARGV[0]
days = (ARGV[1] || 21).to_i

# LOG = "/cm/shared/apps/sge/6.2u5p2/default/common/accounting"
LOG = "/cm/shared/apps/sge/var/default/common/accounting"

COLS = %w{ qname hostname group owner job_name job_number account priority submission_time start_time end_time failed exit_status ru_wallclock project department granted_pe slots task_number cpu mem io category iow pe_taskid maxvmem arid ar_submission_time }.map(&:to_sym)
COL_IDX = Hash[COLS.each_with_index.to_a]

QUEUES = Hash.new do |h,k|
  h[k] = k
end
USERS = Hash.new do |h,k|
  h[k] = k
end

user_ids = UserIDs.new("qstat-user-to-ids.json", false)


class Task
  attr_reader :submission_time, :start_time, :end_time, :queue, :owner, :parts

  def initialize(submission_time, start_time, end_time, queue, owner)
    @submission_time = submission_time
    @start_time = start_time
    @end_time = end_time
    @queue = queue
    @owner = owner
  end
end

class CurrentTasks
  def initialize
    @active = SortedSet.new
    @running_count = Hash.new(0)
    @queued_count = Hash.new(0)
  end

  def process(task)
    if task.start_time
      @active << TaskEvent.new(:start, task.start_time, task)
      @running_count[task.owner] += 1
    else
      @active << TaskEvent.new(:submission, task.submission_time, task)
      @queued_count[task.owner] += 1
    end
    shift_to(task.end_time) if task.end_time
    self
  end

  def tasks_per_user
    { :running=>@running_count, :queued=>@queued_count }
  end

  def on_shift(&block)
    @on_shift_block = block
  end

  private

  def shift_to(time)
#   $stderr.puts "Shift to #{ time }"

    # which events happened before time?
    while task_event = @active.first and task_event.time >= time
      @active.delete(task_event)

      case task_event.event
      when :start
        @running_count[task_event.task.owner] -= 1

        # queue submission event
        @active << TaskEvent.new(:submission, task_event.task.submission_time, task_event.task)
        @queued_count[task_event.task.owner] += 1

      when :submission
        @queued_count[task_event.task.owner] -= 1
      end

      if @on_shift_block
        @on_shift_block.call(task_event.time, tasks_per_user)
      end
    end

    if @on_shift_block
      @on_shift_block.call(time, tasks_per_user)
    end
  end

  class TaskEvent
    attr_reader :event, :time, :task
    
    def initialize(event, time, task)
      @event = event
      @task = task
      @time = time
    end

    def <=>(other)
      # sort by time in reverse (youngest task first)
      c = (other.time <=> self.time)
      if c == 0
        c = (other.task.object_id <=> self.task.object_id)
      end
      c
    end
  end
end


class Series
  def initialize
    @timestamps = []
    @running = Hash.new do |hash, user|
      hash[user] = [0] * @timestamps.size
    end
    @queued = Hash.new do |hash, user|
      hash[user] = [0] * @timestamps.size
    end

    @current_batch = []
    @batch_timestamp = nil
  end

  def for_json(user_ids)
    { :timestamps=>@timestamps,
      :series=>{
        :running=>(@running.sort_by do |user, data|
          user
        end.map do |user, data|
          { :name=>user, :user_id=>user_ids.user_to_id(user), :points=>data }
        end),
        :queued=>(@queued.sort_by do |user, data|
          user
        end.map do |user, data|
          { :name=>user, :user_id=>user_ids.user_to_id(user), :points=>data }
        end)
      }
    }
  end

  def insert(time, stats)
    # round to nearest 60-second precision
    time = (time.to_f / 60.0).ceil * 60

    if @batch_timestamp and @batch_timestamp > time
      # process batch: log first event
      real_insert(@current_batch.first[0], @current_batch.first[1])

      if @current_batch.size > 1
        # log last event, one second earlier
        real_insert(@current_batch.last[0] - 1, @current_batch.last[1])
      end

      @current_batch = []
    end

    unless @current_batch.last == [ time, stats ]
      @current_batch << [ time, stats ]
    end
    @batch_timestamp = time
  end

  private

  def real_insert(time, stats)
    # ignore out-of-sync timestamps
    return if @timestamps.first and @timestamps.first <= time
    raise "Unsorted! #{ @timestamps.first } <= #{ time }" if @timestamps.first and @timestamps.first <= time

    stats[:running].each do |owner, count|
      @running[owner].unshift(count)
    end
    stats[:queued].each do |owner, count|
      @queued[owner].unshift(count)
    end
    @timestamps.unshift(time)
    @running.each do |owner, points|
      points.unshift(0) until points.size == @timestamps.size
    end
    @queued.each do |owner, points|
      points.unshift(0) until points.size == @timestamps.size
    end
  end
end


series = Series.new

current_tasks = CurrentTasks.new
current_tasks.on_shift do |time, stats|
  series.insert(time, stats)
end


if true # false #true # false
# start with current jobs
$stderr.puts "Loading current jobs"
job_details = Qstat.job_details(Qstat.running_job_ids)
Qstat.jobs_per_queue.each do |queue, jobs_per_state|
  jobs_per_state.each do |state, jobs|
    if state=~/[rq]/
      jobs.each do |job|
        if job[:submission_time]
          # queued job
          submission_time = Time.parse(job[:submission_time]).to_i
        else
          # running job
          submission_time = job_details[job[:job_number]]["JB_submission_time"].to_i
        end
        if job[:start_time]
          # running job
          start_time = Time.parse(job[:start_time]).to_i
        else
          # queued job
          start_time = nil
        end

        task = Task.new(submission_time,
                        start_time,
                        nil, # no end_time
                        QUEUES[queue],
                        USERS[job[:owner]])
        current_tasks.process(task)
      end
    end
  end
end
end

# process log (backwards)
$stderr.puts "Processing accounting file"
Elif.open(LOG) do |f|
  line_number = 0
  f.each_line do |line|
    line_number += 1
    $stderr.puts "Processed #{ line_number } lines" if line_number % 1_000 == 0

    unless line =~ /^#/
      parts = line.strip.split(":")

      qname = parts[COL_IDX[:qname]]
      submission_time = parts[COL_IDX[:submission_time]].to_i
      start_time = parts[COL_IDX[:start_time]].to_i
      end_time = parts[COL_IDX[:end_time]].to_i

      unless qname == "interactive" or submission_time == 0 or start_time == 0 or end_time == 0
        if submission_time > start_time or submission_time > end_time
          puts line
          raise "Problem!"
        end

        task = Task.new(submission_time,
                        start_time,
                        end_time,
                        QUEUES[qname],
                        USERS[parts[COL_IDX[:owner]]])
        current_tasks.process(task)

#       p line
#       p end_time
#       p queue

        if parts[COL_IDX[:end_time]].to_i < Time.now.to_i - (60*60*24*days)
          $stderr.puts "JSON"
          File.open(outfile, "w") do |json|
            JSON.dump(series.for_json(user_ids), json)
          end
          exit
        end
      end
    end
  end
end

