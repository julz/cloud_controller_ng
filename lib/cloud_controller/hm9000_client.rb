require 'set'

module VCAP::CloudController
  class HM9000Client
    def initialize(message_bus, config)
      @message_bus = message_bus
      @config = config
    end

    # def healthy_instances(app)
    #   healthy_instances_bulk([app])[app.guid] || 0
    # end

    def healthy_instances(app)
      response = make_request(app)

      if response.nil? || response["instance_heartbeats"].nil?
        return 0
      end

      running_indices = Set.new
      response["instance_heartbeats"].each do |instance|
        if instance["index"] < app.instances && (instance["state"] == "RUNNING" || instance["state"] == "STARTING")
          running_indices.add(instance["index"])
        end
      end

      return running_indices.length
    end

    def healthy_instances_bulk(apps)
      apps.inject({}) do |instances, app|
        instances.update(app => healthy_instances(app))
      end
    end

    # def healthy_instances_bulk(apps)
    #   return {} if apps.empty?
    #   response = make_bulk_request(apps) || {}
    #
    #   data = {}
    #   apps.each do |app|
    #     instance = response[app.guid] || {}
    #
    #     count = 0
    #     if instance["instance_heartbeats"]
    #       running_indices = Set.new
    #       instance["instance_heartbeats"].each do |heartbeats|
    #         if heartbeats["index"] < app.instances && (heartbeats["state"] == "RUNNING" || heartbeats["state"] == "STARTING")
    #           running_indices.add(heartbeats["index"])
    #         end
    #       end
    #       count = running_indices.length
    #     end
    #     data[app.guid] = count
    #   end
    #
    #   data
    # end

    def find_crashes(app)
      response = make_request(app)
      if !response
        return []
      end

      crashing_instances = []
      response["instance_heartbeats"].each do |instance|
        if instance["state"] == "CRASHED"
          crashing_instances << {"instance" => instance["instance"], "since" => instance["state_timestamp"]}
        end
      end

      crashing_instances
    end

    def find_flapping_indices(app)
      response = make_request(app)
      if !response
        return []
      end

      flapping_indices = []

      response["crash_counts"].each do |crash_count|
        if crash_count["crash_count"] >= @config[:flapping_crash_count_threshold]
          flapping_indices << {"index" => crash_count["instance_index"], "since" => crash_count["created_at"]}
        end
      end

      flapping_indices
    end

    private

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

    def make_bulk_request(apps)
      message = apps.collect do |app|
        { droplet: app.guid, version: app.version }
      end

      logger.info("requesting app.state.bulk", message: message)
      responses = @message_bus.synchronous_request("app.state.bulk", message, { timeout: 5 })
      logger.info("received app.state.bulk response", { message: message, responses: responses })
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
