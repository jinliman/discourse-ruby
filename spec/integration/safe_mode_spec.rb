require 'rails_helper'

RSpec.describe 'Safe mode' do
  describe 'entering safe mode' do
    context 'when no params are given' do
      it 'should redirect back to safe mode page' do
        post '/safe-mode'

        expect(response.status).to redirect_to(safe_mode_path)
      end
    end
  end
end
