require "spec_helper"

module VCAP::CloudController
  describe SyslogDrainUrlsController do
    let(:app_obj) { AppFactory.make }
    let(:instance1) { UserProvidedServiceInstance.make(space: app_obj.space) }
    let(:instance2) { UserProvidedServiceInstance.make(space: app_obj.space) }
    let!(:binding_with_drain1) { ServiceBinding.make(syslog_drain_url: 'fishfinger', app: app_obj, service_instance: instance1) }
    let!(:binding_with_drain2) { ServiceBinding.make(syslog_drain_url: 'foobar', app: app_obj, service_instance: instance2) }

    before do
      @bulk_user = "bulk_user"
      @bulk_password = "bulk_password"

      described_class.configure(TestConfig.config)
    end

    describe "GET /v2/syslog_drain_urls" do
      it "requires admin authentication" do
        get "/v2/syslog_drain_urls"
        expect(last_response.status).to eq(401)

        authorize "bar", "foo"
        get "/v2/syslog_drain_urls"
        expect(last_response.status).to eq(401)
      end

      describe "when the user is authenticated" do
        before do
          authorize @bulk_user, @bulk_password
        end

        it "returns a list of syslog drain urls" do
          get '/v2/syslog_drain_urls', '{}'
          expect(last_response).to be_successful
          expect(decoded_results).to eq({
            app_obj.guid => [ 'fishfinger', 'foobar' ]
          })
        end

        context "when an app has no service binding" do
          let!(:app_obj_no_binding) { AppFactory.make }
          it "does not include that app" do
            get '/v2/syslog_drain_urls', '{}'
            expect(last_response).to be_successful
            expect(decoded_results).not_to have_key(app_obj_no_binding.guid)
          end
        end

        context "when an app's bindings have no syslog_drain_url" do
          let(:binding) { ServiceBinding.make() }
          let!(:app_obj_no_drain) { binding.app }

          it "does not include that app" do
            get '/v2/syslog_drain_urls', '{}'
            expect(last_response).to be_successful
            expect(decoded_results).not_to have_key(app_obj_no_drain.guid)
          end
        end

        def decoded_results
          decoded_response.fetch("results")
        end

        describe "paging" do
          before do
            8.times do
              app_obj = AppFactory.make
              instance = UserProvidedServiceInstance.make(space: app_obj.space)
              ServiceBinding.make(syslog_drain_url: 'fishfinger', app: app_obj, service_instance: instance)
            end
          end

          it "respects the batch_size parameter" do
            [3,5].each do |size|
              get "/v2/syslog_drain_urls", { "batch_size" => size }
              expect(last_response).to be_successful
              expect(decoded_results.size).to eq(size)
            end
          end

          it "returns non-intersecting results when token is supplied" do
            get "/v2/syslog_drain_urls", {
              "batch_size" => 2,
              "next_id" => 0
            }

            saved_results = decoded_response["results"].dup
            expect(saved_results.size).to eq(2)

            get "/v2/syslog_drain_urls", {
              "batch_size" => 2,
              "next_id" => decoded_response["next_id"],
            }

            new_results = decoded_response["results"].dup

            expect(new_results.size).to eq(2)
            saved_results.each do |guid, drains|
              expect(new_results).not_to have_key(guid)
            end
          end

          it "should eventually return entire collection, batch after batch" do
            apps = {}
            total_size = App.count

            token = 0
            while apps.size < total_size do
              get "/v2/syslog_drain_urls", {
                "batch_size" => 2,
                "next_id" => token,
              }

              expect(last_response.status).to eq(200)
              token = decoded_response["next_id"]
              apps.merge!(decoded_response["results"])
            end

            expect(apps.size).to eq(total_size)
            get "/v2/syslog_drain_urls", {
              "batch_size" => 2,
              "next_id" => token,
            }
            expect(decoded_response["results"].size).to eq(0)
          end

          context "when an app has no service_bindings" do
            before do
              App.order(:id).all[1].service_bindings_dataset.destroy
            end

            it "does not affect the paging results" do
              get "/v2/syslog_drain_urls", {
                "batch_size" => 2,
                "next_id" => 0
              }

              saved_results = decoded_response["results"].dup
              expect(saved_results.size).to eq(2)
            end
          end

          context "when an app has no syslog_drain_urls" do
            before do
              App.order(:id).all[1].service_bindings.first.update(syslog_drain_url: nil)
            end

            it "does not affect the paging results" do
              get "/v2/syslog_drain_urls", {
                "batch_size" => 2,
                "next_id" => 0
              }

              saved_results = decoded_response["results"].dup
              expect(saved_results.size).to eq(2)
            end
          end
        end
      end
    end
  end
end
