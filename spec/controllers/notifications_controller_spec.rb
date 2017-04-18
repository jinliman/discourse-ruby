require 'rails_helper'

describe NotificationsController do

  context 'when logged in' do
    let!(:user) { log_in }

    describe '#index' do
      it 'should succeed for recent' do
        xhr :get, :index, recent: true
        expect(response).to be_success
      end

      it 'should succeed for history' do
        xhr :get, :index
        expect(response).to be_success
      end

      it 'should mark notifications as viewed' do
        notification = Fabricate(:notification, user: user)
        expect(user.reload.unread_notifications).to eq(1)
        expect(user.reload.total_unread_notifications).to eq(1)
        xhr :get, :index, recent: true
        expect(user.reload.unread_notifications).to eq(0)
        expect(user.reload.total_unread_notifications).to eq(1)
      end

      it 'should not mark notifications as viewed if silent param is present' do
        notification = Fabricate(:notification, user: user)
        expect(user.reload.unread_notifications).to eq(1)
        expect(user.reload.total_unread_notifications).to eq(1)
        xhr :get, :index, recent: true, silent: true
        expect(user.reload.unread_notifications).to eq(1)
        expect(user.reload.total_unread_notifications).to eq(1)
      end

      context 'when username params is not valid' do
        it 'should raise the right error' do
          expect { xhr :get, :index, username: 'somedude' }
            .to raise_error(Discourse::InvalidParameters)
        end
      end
    end

    it 'should succeed' do
      xhr :put, :mark_read
      expect(response).to be_success
    end

    it "can update a single notification" do
      notification = Fabricate(:notification, user: user)
      notification2 = Fabricate(:notification, user: user)
      xhr :put, :mark_read, id: notification.id
      expect(response).to be_success

      notification.reload
      notification2.reload

      expect(notification.read).to eq(true)
      expect(notification2.read).to eq(false)
    end

    it "updates the `read` status" do
      notification = Fabricate(:notification, user: user)
      expect(user.reload.unread_notifications).to eq(1)
      expect(user.reload.total_unread_notifications).to eq(1)
      xhr :put, :mark_read
      user.reload
      expect(user.reload.unread_notifications).to eq(0)
      expect(user.reload.total_unread_notifications).to eq(0)
    end
  end

  context 'when not logged in' do
    it 'should raise an error' do
      expect { xhr :get, :index, recent: true }.to raise_error(Discourse::NotLoggedIn)
    end
  end

end
