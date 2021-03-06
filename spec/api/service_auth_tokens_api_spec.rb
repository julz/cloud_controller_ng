require 'spec_helper'
require 'rspec_api_documentation/dsl'

resource "ServiceAuthTokens", :type => :api do
  let(:admin_auth_header) { headers_for(admin_user, :admin_scope => true)["HTTP_AUTHORIZATION"] }
  authenticated_request

  before do
    reset_database

    3.times do
      VCAP::CloudController::ServiceAuthToken.make
    end
  end

  let(:guid) { VCAP::CloudController::ServiceAuthToken.first.guid }

  standard_parameters

  field :label, "Human readable name for the auth token",
        required: true, example_values: ["Nic-Token"]
  field :provider, "Human readable name of service provider",
        required: true, example_values: ["Face-Offer"]
  field :token, "The secret auth token used for authenticating",
        required: true

  standard_model_object :service_auth_token

  get "/v2/service_auth_tokens" do
    describe "querying by label" do
      let(:q) { "label:Nic-Token"}

      before do
        VCAP::CloudController::ServiceAuthToken.make :label => "Nic-Token"
      end

      example "filters the result set to the given label" do
        client.get "/v2/service_auth_tokens", params, headers

        status.should == 200

        standard_paginated_response_format? parsed_response

        parsed_response["resources"].size.should == 1

        standard_entity_response(
          parsed_response["resources"].first,
          :service_auth_token,
          :label => "Nic-Token")
      end
    end

    describe "querying by provider" do
      let(:q) { "provider:Face-Offer"}

      before do
        VCAP::CloudController::ServiceAuthToken.make :provider => "Face-Offer"
      end

      example "filters the result set to the given label" do
        client.get "/v2/service_auth_tokens", params, headers

        status.should == 200

        standard_paginated_response_format? parsed_response

        parsed_response["resources"].size.should == 1

        standard_entity_response(
          parsed_response["resources"].first,
          :service_auth_token,
          :provider => "Face-Offer")
      end
    end
  end
end
