module VCAP::CloudController
  class AppFetcher
    def initialize(user)
      @user = user
    end

    def fetch(app_guid)
      dataset.where(:"#{AppModel.table_name}__guid" => app_guid).first
    end

    private

    def dataset
      ds = AppModel.dataset.eager(:processes)
      return ds if @user.admin?

      ds.select_all(AppModel.table_name).
        join(Space.table_name, guid: :space_guid).where(space_guid: @user.spaces_dataset.select(:guid)).
        join(Organization.table_name, id: :organization_id).where(status: 'active')
    end
  end
end
