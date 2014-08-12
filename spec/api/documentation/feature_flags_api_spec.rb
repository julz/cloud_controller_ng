require "spec_helper"
require "rspec_api_documentation/dsl"

resource "Feature Flags (experimental)", :type => :api do
  let(:admin_auth_header) { admin_headers["HTTP_AUTHORIZATION"] }

  authenticated_request

  shared_context "name_parameter" do
    parameter :name, "The name of the feature flag", valid_values: ["user_org_creation", "app_bits_upload", "private_domain_creation", "app_scaling"]
  end

  shared_context "updatable_fields" do
    field :enabled, "The state of the feature flag.", required: true, valid_values: [true, false]
    field :error_message, "The custom error message for the feature flag.", example_values: ["error message"]
  end

  get "/v2/config/feature_flags" do
    example "Get all feature flags" do
      VCAP::CloudController::FeatureFlag.create(name: "private_domain_creation", enabled: false, error_message: "foobar")

      client.get "/v2/config/feature_flags", {}, headers

      expect(status).to eq(200)
      expect(parsed_response.length).to eq(3)
      expect(parsed_response).to include(
        {
          'name'          => 'user_org_creation',
          'default_value' => false,
          'enabled'       => false,
          'error_message' => nil,
          'overridden'    => false,
          'url'           => '/v2/config/feature_flags/user_org_creation'
        })
      expect(parsed_response).to include(
        {
          'name'          => 'app_bits_upload',
          'default_value' => true,
          'enabled'       => true,
          'overridden'    => false,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/app_bits_upload'
        })
      expect(parsed_response).to include(
        {
          'name'          => 'app_scaling',
          'default_value' => true,
          'enabled'       => true,
          'overridden'    => false,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/app_scaling'
        })
      expect(parsed_response).to include(
        {
          'name'          => 'private_domain_creation',
          'default_value' => true,
          'enabled'       => false,
          'overridden'    => true,
          'error_message' => 'foobar',
          'url'           => '/v2/config/feature_flags/private_domain_creation'
        })
    end
  end

  get "/v2/config/feature_flags/app_bits_upload" do
    example "Get the App Bits Upload feature flag" do
      explanation "When disabled, only admin users can upload app bits"
      client.get "/v2/config/feature_flags/app_bits_upload", {}, headers

      expect(status).to eq(200)
      expect(parsed_response).to eq(
        {
          'name'          => 'app_bits_upload',
          'default_value' => true,
          'enabled'       => true,
          'overridden'    => false,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/app_bits_upload'
        })
    end
  end

  get "/v2/config/feature_flags/app_scaling" do
    example "Get the App Scaling feature flag" do
      explanation "When disabled, only admin users can perform scaling operations (i.e. change memory, disk or instances)"
      client.get "/v2/config/feature_flags/app_bits_upload", {}, headers

      expect(status).to eq(200)
      expect(parsed_response).to eq(
        {
          'name'          => 'app_scaling',
          'default_value' => true,
          'enabled'       => true,
          'overridden'    => false,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/app_scaling'
        })
    end
  end

  get "/v2/config/feature_flags/user_org_creation" do
    example "Get the User Org Creation feature flag" do
      explanation "When enabled, any user can create an organization via the API."
      client.get "/v2/config/feature_flags/user_org_creation", {}, headers

      expect(status).to eq(200)
      expect(parsed_response).to eq(
        {
          'name'          => 'user_org_creation',
          'default_value' => false,
          'enabled'       => false,
          'overridden'    => false,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/user_org_creation'
        })
    end
  end

  get "/v2/config/feature_flags/private_domain_creation" do
    example "Get the Private Domain Creation feature flag" do
      explanation "When enabled, an organization manager can create private domains for that organization."
      client.get "/v2/config/feature_flags/private_domain_creation", {}, headers

      expect(status).to eq(200)
      expect(parsed_response).to eq(
        {
          'name'          => 'private_domain_creation',
          'default_value' => true,
          'enabled'       => true,
          'overridden'    => false,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/private_domain_creation'
        })
    end
  end

  put "/v2/config/feature_flags/:name" do
    include_context "name_parameter"
    include_context "updatable_fields"

    example "Set a feature flag" do
      client.put "/v2/config/feature_flags/user_org_creation", fields_json, headers

      expect(status).to eq(200)
      expect(parsed_response).to eq(
        {
          'name'          => 'user_org_creation',
          'default_value' => false,
          'enabled'       => true,
          'overridden'    => true,
          'error_message' => nil,
          'url'           => '/v2/config/feature_flags/user_org_creation'
        })
    end
  end

  delete "/v2/config/feature_flags/:name" do
    include_context "name_parameter"

    example "Unset a feature flag" do
      VCAP::CloudController::FeatureFlag.create(name: "private_domain_creation", enabled: false)
      client.delete "/v2/config/feature_flags/private_domain_creation", "{}", headers
      expect(status).to eq(204)
      expect(VCAP::CloudController::FeatureFlag.find(name: "private_domain_creation")).to be_nil
    end
  end
end
