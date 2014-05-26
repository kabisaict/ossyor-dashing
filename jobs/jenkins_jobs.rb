require 'net/http'
require 'json'

jenkins_host = 'oss-ci.ddns.htc.nl.philips.com'
jenkins_view = 'ossyor'
jenkins_port = '8080'

jenkins_reachable = false
begin
  http = Net::HTTP.new(jenkins_host,jenkins_port)
  url  = '/view/%s/api/json?tree=jobs[name,color]' % jenkins_view
  response = http.request(Net::HTTP::Get.new(url))
  jenkins_reachable = true
rescue
  puts 'Jenkins not reachable, skipping updates'
end

SCHEDULER.every '30s', :first_in => 0 do
  http = Net::HTTP.new(jenkins_host,jenkins_port)
  url  = '/view/%s/api/json?tree=jobs[name,color]' % jenkins_view

  response = http.request(Net::HTTP::Get.new(url))
  jobs     = JSON.parse(response.body)['jobs']

  url  = '/queue/api/json?tree=items[inQueueSince,task[color,name]]'
  response = http.request(Net::HTTP::Get.new(url))
  queue_items    = JSON.parse(response.body)['items']

  # Figure out of build is stalled...
  # http://oss-ci.ddns.htc.nl.philips.com:8080/job/ossyor_feature-developers-page-readability/2/api/json?tree=building,duration,estimatedDuration
  #
  # Maybe use:
  # /api/xml?tree=computer[executors[currentExecutable[url]],oneOffExecutors[currentExecutable[url]]]&xpath=//url&wrapper=builds

  queue = {}

  if queue_items
    queue_items.sort_by { |item| item['inQueueSince'] }
    queue_items.reverse!
    queue_items = queue_items[0..7]
    position = 1
    queue_items.map do |item|
      name = item['task']['name']
      queue[name] ||= []
      queue[name] << position
      position += 1
    end
  end

  if jobs
    jobs.map! { |job|
      color = 'grey'

      case job['color']
      when 'blue', 'blue_anime', 'red', 'red_anime', 'aborted', 'aborted_anime', 'grey', 'grey_anime'
        color = job['color']
      end

      { name: job['name'], state: color, queuePositions: queue[job['name']] }
    }

    jobs.sort_by { |job| job['name'] }

    send_event('jenkins_jobs', { jobs: jobs })
  end
end if jenkins_reachable

