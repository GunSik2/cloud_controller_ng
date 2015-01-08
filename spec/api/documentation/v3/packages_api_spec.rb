require 'spec_helper'
require 'awesome_print'
require 'rspec_api_documentation/dsl'

resource 'Packages (Experimental)', type: :api do
  let(:tmpdir) { Dir.mktmpdir }
  let(:valid_zip) {
    zip_name = File.join(tmpdir, 'file.zip')
    TestZip.create(zip_name, 1, 1024)
    File.new(zip_name)
  }

  let(:user) { VCAP::CloudController::User.make }
  let(:user_header) { headers_for(user)['HTTP_AUTHORIZATION'] }
  header 'AUTHORIZATION', :user_header

  def do_request_with_error_handling
    do_request
    if response_status == 500
      error = MultiJson.load(response_body)
      ap error
      raise error['description']
    end
  end

  context 'standard endpoints' do
    get '/v3/packages/:guid' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }

      let(:package_model) do
        VCAP::CloudController::PackageModel.make(app_guid: app_model.guid)
      end

      let(:guid) { package_model.guid }
      let(:app_guid) { app_model.guid }

      before do
        space.organization.add_user user
        space.add_developer user
      end

      example 'Get a Package' do
        expected_response = {
          'type'   => package_model.type,
          'guid'   => guid,
          'hash'   => nil,
          'state'  => 'PENDING',
          'error'  => nil,
          'created_at' => package_model.created_at.as_json,
          '_links' => {
            'self'      => { 'href' => "/v3/packages/#{guid}" },
            'app' => { 'href' => "/v3/apps/#{app_guid}" },
          }
        }

        do_request_with_error_handling

        parsed_response = MultiJson.load(response_body)
        expect(response_status).to eq(200)
        expect(parsed_response).to match(expected_response)
      end
    end

    post '/v3/apps/:guid/packages' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:space_guid) { space.guid }
      let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
      let(:guid) { app_model.guid }

      before do
        space.organization.add_user(user)
        space.add_developer(user)
      end

      parameter :guid, 'GUID of the app that is going to use the package', required: true
      parameter :type, 'Package type', required: true, valid_values: ['bits', 'docker']
      parameter :bits, 'A binary zip file containing the package bits', required: false

      context 'when the type is bits' do
        let(:type) { 'bits' }
        let(:packages_params) do
          {
            type: type,
            bits_name: 'application.zip',
            bits_path: "#{tmpdir}/application.zip",
          }
        end

        let(:request_body_example) do
          <<-eos.gsub(/^ */, '')
            Content-type: multipart/form-data, boundary=AaB03x
            --AaB03x
            Content-Disposition: form-data; name="type"

            #{type}
            --AaB03x
            Content-Disposition: form-data; name="bits"; filename="application.zip"
            Content-Type: application/zip
            Content-Length: 123
            Content-Transfer-Encoding: binary

            &lt;&lt;binary artifact bytes&gt;&gt;
            --AaB03x
          eos
        end

        example 'Create a Package with application bits' do
          expect {
            do_request packages_params
          }.to change { VCAP::CloudController::PackageModel.count }.by(1)

          package = VCAP::CloudController::PackageModel.last

          job = Delayed::Job.last
          expect(job.handler).to include(package.guid)
          expect(job.guid).not_to be_nil

          expected_response = {
            'guid' => package.guid,
            'type' => type,
            'hash' => nil,
            'state' => 'PENDING',
            'error' => nil,
            'created_at' => package.created_at.as_json,
            '_links' => {
              'self' => { 'href' => "/v3/packages/#{package.guid}" },
              'app' => { 'href' => "/v3/apps/#{app_model.guid}" },
            }
          }

          parsed_response = MultiJson.load(response_body)
          expect(response_status).to eq(201)
          expect(parsed_response).to match(expected_response)
        end
      end

      context 'when the type is docker' do
        let(:type) { 'docker' }
        let(:packages_params) do
          {
            type: type,
          }
        end

        let(:request_body_example) do
          <<-eos.gsub(/^ */, '')
            Content-type: multipart/form-data, boundary=AaB03x
            --AaB03x
            Content-Disposition: form-data; name="type"

            #{type}
            --AaB03x
          eos
        end

        example 'Create a Package with docker image' do
          expect {
            do_request packages_params
          }.to change { VCAP::CloudController::PackageModel.count }.by(1)

          package = VCAP::CloudController::PackageModel.last

          expected_response = {
            'guid' => package.guid,
            'type' => type,
            'hash' => nil,
            'state' => 'READY',
            'error' => nil,
            'created_at' => package.created_at.as_json,
            '_links' => {
              'self' => { 'href' => "/v3/packages/#{package.guid}" },
              'app' => { 'href' => "/v3/apps/#{app_model.guid}" },
            }
          }

          parsed_response = MultiJson.load(response_body)
          expect(response_status).to eq(201)
          expect(parsed_response).to match(expected_response)
        end
      end
    end

    delete '/v3/packages/:guid' do
      let(:space) { VCAP::CloudController::Space.make }
      let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }

      let!(:package_model) do
        VCAP::CloudController::PackageModel.make(app_guid: app_model.guid)
      end

      let(:guid) { package_model.guid }
      let(:app_guid) { app_model.guid }

      before do
        space.organization.add_user user
        space.add_developer user
      end

      example 'Delete a Package' do
        expect {
          do_request_with_error_handling
        }.to change { VCAP::CloudController::PackageModel.count }.by(-1)
        expect(response_status).to eq(204)
      end
    end
  end
end
