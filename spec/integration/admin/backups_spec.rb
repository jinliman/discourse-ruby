require 'rails_helper'

RSpec.describe "Managing Backups" do
  let(:admin) { Fabricate(:admin) }

  before do
    sign_in(admin)
  end

  describe 'rolling back a restore' do
    it 'should rollback the restore' do
      BackupRestore.expects(:rollback!)

      post "/admin/backups/rollback.json"

      expect(response).to be_success
    end

    it 'should not allow rollback via a GET request' do
      expect { get "/admin/backups/rollback.json" }
        .to raise_error(ActionController::RoutingError)
    end
  end

  describe 'cancelling a backup' do
    it "should cancel an backup" do
      BackupRestore.expects(:cancel!)

      delete "/admin/backups/cancel.json"

      expect(response).to be_success
    end

    it 'should not allow cancel via a GET request' do
      expect { get "/admin/backups/cancel.json" }
        .to raise_error(ActionController::RoutingError)
    end
  end
end
