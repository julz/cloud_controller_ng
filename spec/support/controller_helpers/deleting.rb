module ControllerHelpers
  shared_examples "deleting a valid object" do |opts|
    describe "deleting a valid object" do
      describe "DELETE #{opts[:path]}/:id" do
        let(:obj) { opts[:model].make }

        subject { delete "#{opts[:path]}/#{obj.guid}", {}, admin_headers }

        before(:all) { reset_database }

        context "when there are no child associations" do
          before do
            if obj.is_a? Service
              # Blueprint makes a ServiceAuthToken. No other model has child associated models created by Blueprint.
              obj.service_auth_token.delete
            end
          end

          it "should return 204" do
            subject
            last_response.status.should == 204
          end

          it "should return an empty response body" do
            subject
            last_response.body.should be_empty
          end
        end

        shared_examples "an object with non-empty child associations" do
          let(:nonempty_one_to_one_or_many) do
            obj.class.associations.select do |association|
              obj.has_one_to_many?(association) || obj.has_one_to_one?(association)
            end
          end

          let!(:associations_without_url) { opts.fetch(:one_to_many_collection_ids_without_url, []).map { |key, child| [key, child.call(obj)] } }
          let!(:associations_with_url) { opts.fetch(:one_to_many_collection_ids, []).map { |key, child| [key, child.call(obj)] } }

          before do
            unless nonempty_one_to_one_or_many.any?
              fail "Test for deleting objects with associations requires at least one associated object to have been created"
            end
          end

          shared_examples "Returns expected error message" do
            it "should return 400" do
              subject
              last_response.status.should == 400
            end

            it "should return the expected response body" do
              subject
              expect(response_description).to include("delete")
              expect(response_description).to include(obj.class.table_name.to_s)
              expect(response_description).to include(nonempty_one_to_one_or_many.join(", "))
            end

            def response_description
              parse(last_response.body)["description"].downcase
            end
          end

          shared_examples "Returns success status" do
            it "should return 204" do
              subject
              last_response.status.should == 204
            end

            it "should return an empty response body" do
              subject
              last_response.body.should be_empty
            end

            it "should delete all the child associations" do
              subject
              (associations_without_url | associations_with_url).map do |name, association|
                association.class[:id => association.id].should be_nil unless obj.class.association_reflection(name)[:type] == :many_to_many || name == :default_users
              end
            end
          end

          context "and the recursive parameter is not passed in" do
            include_examples "Returns expected error message"
          end

          context "and the recursive param is passed in" do
            subject { delete "#{opts[:path]}/#{obj.guid}?recursive=#{recursive}", {}, admin_headers }

            context "and its false" do
              let(:recursive) { "false" }
              include_examples "Returns expected error message"
            end

            context "and its true" do
              let(:recursive) { "true" }
              include_examples "Returns success status"
            end
          end
        end

        unless( opts.fetch(:one_to_many_collection_ids, {}).empty? && opts.fetch(:one_to_many_collection_ids_without_url, {}).empty? )
          context "when there are non-empty child associations" do
            include_examples "an object with non-empty child associations"
          end
        end
      end
    end
  end
end
