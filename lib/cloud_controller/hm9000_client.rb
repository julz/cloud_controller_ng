require 'set'

module VCAP::CloudController
  class HM9000Client
    MAX_APPS_PER_BULK_REQUEST = 50
    ERROR_SENTINEL_VALUE = -1

    def initialize(message_bus, config)
      @message_bus = message_bus
      @config = config
    end

    def healthy_instances(app)
      healthy_instances_bulk([app])[app.guid]
    end

    def healthy_instances_bulk(apps)
      return {} if apps.empty?
      response = make_multiple_bulk_requests(apps, MAX_APPS_PER_BULK_REQUEST)

      apps.each_with_object({}) do |app, result|
        instance = response[app.guid] || {}
        result[app.guid] = instance["instance_heartbeats"] ? count_heartbeats(app, instance["instance_heartbeats"]) : ERROR_SENTINEL_VALUE
      end
    end

    def find_crashes(app)
      response = make_request(app)
      return [] unless response

      response["instance_heartbeats"].each_with_object([]) do |instance, result|
        if instance["state"] == "CRASHED"
          result << {"instance" => instance["instance"], "since" => instance["state_timestamp"]}
        end
      end
    end

    def find_flapping_indices(app)
      response = make_request(app)
      return [] unless response

      response["crash_counts"].each_with_object([]) do |crash_count, result|
        if crash_count["crash_count"] >= @config[:flapping_crash_count_threshold]
          result << {"index" => crash_count["instance_index"], "since" => crash_count["created_at"]}
        end
      end
    end

    private

    def count_heartbeats(app, instance_heartbeats)
      instance_heartbeats.each_with_object(Set.new) do |heartbeats, result|
        if heartbeats["index"] < app.instances && (heartbeats["state"] == "RUNNING" || heartbeats["state"] == "STARTING")
          result.add(heartbeats["index"])
        end
      end.length
    end

    def make_multiple_bulk_requests(apps, apps_per_request)
      apps.each_slice(apps_per_request).reduce({}) do |result, slice|
        result.merge(make_bulk_request(slice) || {})
      end
    end

    def make_bulk_request(apps)
      message = apps.collect do |app|
        { droplet: app.guid, version: app.version }
      end

      logger.info("requesting app.state.bulk", message: message)
      responses = @message_bus.synchronous_request("app.state.bulk", message, { timeout: 5 })
      logger.info("received app.state.bulk response", { message: message, responses: responses })
      responses.first
    end

    def make_request(app)
      message = { droplet: app.guid, version: app.version }
      logger.info("requesting app.state", message)
      responses = @message_bus.synchronous_request("app.state", message, { timeout: 2 })
      logger.info("received app.state response", { message: message, responses: responses })
      return if responses.empty?

      response = responses.first
      return if response.empty?

      response
    end

    def logger
      @logger ||= Steno.logger("cc.healthmanager.client")
    end
  end
end
