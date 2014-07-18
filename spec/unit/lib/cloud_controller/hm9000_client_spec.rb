require "spec_helper"

def generate_hm_api_response(app, running_instances, crash_counts=[])
  result = {
    droplet: app.guid,
    version: app.version,
    desired: {
      id: app.guid,
      version: app.version,
      instances: app.instances,
      state: app.state,
      package_state: app.package_state,
    },
    instance_heartbeats: [],
    crash_counts: []
  }

  running_instances.each do |running_instance|
    result[:instance_heartbeats].push({
                                        droplet: app.guid,
                                        version: app.version,
                                        instance: running_instance[:instance_guid] || Sham.guid,
                                        index: running_instance[:index],
                                        state: running_instance[:state],
                                        state_timestamp: 3.141
                                      })
  end

  crash_counts.each do |crash_count|
    result[:crash_counts].push({
                                  droplet: app.guid,
                                  version: app.version,
                                  instance_index: crash_count[:instance_index],
                                  crash_count: crash_count[:crash_count],
                                  created_at: 1234567
                               })
  end

  JSON.parse(result.to_json)
end

module VCAP::CloudController
  describe VCAP::CloudController::HM9000Client do
    let(:app0instances) { 1 }
    let(:app0) { AppFactory.make(instances: app0instances) }
    let(:app1) { AppFactory.make(instances: 1) }
    let(:app2) { AppFactory.make(instances: 1) }
    let(:app_hm_doesnt_know_about) { AppFactory.make(instances: 1) }
    let(:app0_request_should_fail) { false }

    let(:hm9000_config) {
      {
        flapping_crash_count_threshold: 3,
      }
    }

    let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "RUNNING" }]) }
    let(:app_1_api_response) { generate_hm_api_response(app1, [{ index: 0, state: "CRASHED" }]) }
    let(:app_2_api_response) { generate_hm_api_response(app2, [{ index: 0, state: "RUNNING" }]) }

    let(:message_bus) { double }
    let(:max_app_bulk_size) { 50 }

    subject(:hm9000_client) { VCAP::CloudController::HM9000Client.new(message_bus, hm9000_config) }

    before do
      allow(message_bus).to receive(:synchronous_request) do |subject, message, options|
        case subject
        when "app.state"
          expect(options).to include(timeout: 2)

          if message[:droplet] == app0.guid && message[:version] == app0.version
            if !app0_request_should_fail
              [app_0_api_response]
            else
              [{}]
            end
          elsif message[:droplet] == app1.guid && message[:version] == app1.version
            [app_1_api_response]
          elsif message[:droplet] == app2.guid && message[:version] == app2.version
            [app_2_api_response]
          else
            [{}]
          end
        when "app.state.bulk"
          expect(options).to include(timeout: 5)
          expect(message.size).to be <= max_app_bulk_size

          result = {}
          message.each do |app_request|
            next if app_request[:droplet] == app_hm_doesnt_know_about
            result[app_request[:droplet]] =
              if app_request[:droplet] == app0.guid && app_request[:version] == app0.version
                if !app0_request_should_fail
                  app_0_api_response
                else
                  {}
                end
              elsif app_request[:droplet] == app1.guid && app_request[:version] == app1.version
                app_1_api_response
              elsif app_request[:droplet] == app2.guid && app_request[:version] == app2.version
                app_2_api_response
              else
                {}
              end
          end
          [result]
        end
      end
    end

    describe "healthy_instances_bulk" do
      context "single app" do
        context "with a single desired and running instance" do
          it "should return the correct number of healthy instances" do
            expect(hm9000_client.healthy_instances(app0)).to eq(1)
          end
        end

        context "when the request fails" do
          let(:app0_request_should_fail) { true }

          it "should return -1" do
            expect(hm9000_client.healthy_instances(app0)).to eq(-1)
          end
        end

        context "with multiple desired instances" do
          let(:app0instances) { 3 }

          context "when all the desired instances are running" do
            let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "RUNNING" }, { index: 1, state: "RUNNING" }, { index: 2, state: "STARTING" }]) }

            it "should return the number of running instances" do
              expect(hm9000_client.healthy_instances(app0)).to eq(3)
            end
          end

          context "when only some of the desired instances are running" do
            let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "RUNNING" }, { index: 2, state: "STARTING" }]) }

            it "should return the number of running instances in the desired range" do
              expect(hm9000_client.healthy_instances(app0)).to eq(2)
            end
          end

          context "when there are extra instances outside of the desired range" do
            let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "RUNNING" }, { index: 2, state: "STARTING" }, { index: 3, state: "RUNNING" }]) }

            it "should only return the number of running instances in the desired range" do
              expect(hm9000_client.healthy_instances(app0)).to eq(2)
            end
          end

          context "when there are multiple instances running on the same index" do
            let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "RUNNING" }, { index: 2, state: "STARTING" }, { index: 2, state: "RUNNING" }]) }

            it "should only count one of the instances" do
              expect(hm9000_client.healthy_instances(app0)).to eq(2)
            end
          end

          context "when some of the desired instances are crashed" do
            let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "RUNNING" }, { index: 1, state: "CRASHED" }, { index: 2, state: "STARTING" }, { index: 2, state: "CRASHED" }]) }

            it "should not count the crashed instances" do
              expect(hm9000_client.healthy_instances(app0)).to eq(2)
            end
          end
        end

        context "when, mysteriously, a response is received that is not empty but is missing instance heartbeats" do
          let(:app_0_api_response) { {droplet: app0.guid, version: app0.version } }

          it "should return ERROR_SENTINEL_VALUE" do
            expect(hm9000_client.healthy_instances(app0)).to eq(-1)
          end
        end
      end

      context "multiple apps" do
        context "when both apps exist" do
          it "should return the correct number of instances for both apps" do
            expect(hm9000_client.healthy_instances_bulk([app0, app1])).to eq({ app0.guid => 1, app1.guid => 0 })
          end
        end

        context "when one of the apps is not found" do
          let(:app_1_api_response) do {} end

          it "returns results for the app that does exist" do
            expect(hm9000_client.healthy_instances_bulk([app0, app_hm_doesnt_know_about])).to include({ app0.guid => 1 })
          end

          it "returns -1 for apps which were not returned" do
            expect(hm9000_client.healthy_instances_bulk([app0, app_hm_doesnt_know_about])).to include({ app_hm_doesnt_know_about.guid => -1 })
          end
        end

        describe "splitting requests to avoid NATS message limits" do
          it "makes multiple small requests if more than 50 apps are requested" do
            apps = ( 1..105 ).map { AppFactory.make }
            expect(message_bus).to receive(:synchronous_request).at_least(3).times
            hm9000_client.healthy_instances_bulk(apps)
          end
        end
      end
    end

    describe "find_crashes" do
      let(:app_0_api_response) { generate_hm_api_response(app0, [{ index: 0, state: "CRASHED", instance_guid: "sham" }, { index: 1, state: "CRASHED", instance_guid: "wow" }, { index: 1, state: "RUNNING" }]) }

      context "when the request fails" do
        let(:app0_request_should_fail) { true }

        it "should return an empty array" do
          expect(hm9000_client.find_crashes(app0)).to eq([])
        end
      end

      context "when the request succeeds" do
        it "should return an array of all the crashed instances" do
          crashes = hm9000_client.find_crashes(app0)
          expect(crashes).to have(2).items
          expect(crashes).to include({ "instance" => "sham", "since" => 3.141 })
          expect(crashes).to include({ "instance" => "wow", "since" => 3.141 })
        end
      end
    end

    describe "find_flapping_indices" do
      let(:app_0_api_response) { generate_hm_api_response(app0, [], [{instance_index:0, crash_count:3}, {instance_index:1, crash_count:1}, {instance_index:2, crash_count:10}]) }

      context "when the request fails" do
        let(:app0_request_should_fail) { true }

        it "should return an empty array" do
          expect(hm9000_client.find_flapping_indices(app0)).to eq([])
        end
      end

      context "when the request succeeds" do
        it "should return an array of all the crashed instances" do
          flapping_indices = hm9000_client.find_flapping_indices(app0)
          expect(flapping_indices).to have(2).items
          expect(flapping_indices).to include({ "index" => 0, "since" => 1234567 })
          expect(flapping_indices).to include({ "index" => 2, "since" => 1234567 })
        end
      end
    end
  end
end
