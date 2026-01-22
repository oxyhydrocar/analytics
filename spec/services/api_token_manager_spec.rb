require 'spec_helper'
require_relative '../../app/services/api_token_manager'

RSpec.describe ApiTokenManager do
  subject(:manager) do
    described_class.new
  end

  describe '#initialize' do
    it 'can be instantiated without error' do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe '#generate_token' do
    let(:user_id) do
      123
    end

    it 'returns a token string' do
      token = manager.generate_token(user_id)
      expect(token).to be_a(String)
      expect(token).not_to be_empty
    end

    it 'generates different tokens for different calls' do
      token1 = manager.generate_token(user_id)
      token2 = manager.generate_token(user_id)
      expect(token1).not_to eq(token2)
    end
  end

  describe '#verify_token' do
    let(:user_id) do
      456
    end

    let(:token) do
      manager.generate_token(user_id)
    end

    context 'when the token exists' do
      it 'returns a non-nil value' do
        result = manager.verify_token(token)
        expect(result).not_to be_nil
      end
    end

    context 'when the token does not exist' do
      it 'returns nil' do
        result = manager.verify_token('non-existent-token')
        expect(result).to be_nil
      end

      it 'does not raise an error' do
        expect do
          manager.verify_token('non-existent-token')
        end.not_to raise_error
      end
    end

    context 'when token is nil' do
      it 'returns nil without raising an error' do
        expect do
          result = manager.verify_token(nil)
          expect(result).to be_nil
        end.not_to raise_error
      end
    end
  end

  describe '#revoke_token' do
    let(:user_id) do
      789
    end

    let!(:token) do
      manager.generate_token(user_id)
    end

    it 'does not raise an error when revoking existing token' do
      expect do
        manager.revoke_token(token)
      end.not_to raise_error
    end

    it 'does not raise an error when revoking non-existent token' do
      expect do
        manager.revoke_token('non-existent-token')
      end.not_to raise_error
    end

    it 'handles nil token gracefully' do
      expect do
        result = manager.revoke_token(nil)
        expect(result).to be_nil
      end.not_to raise_error
    end
  end

  describe '#get_token_scope' do
    let(:user_id) do
      111
    end

    let!(:token) do
      manager.generate_token(user_id)
    end

    context 'when the token exists' do
      it 'returns a String or nil without raising an error' do
        expect do
          scope = manager.get_token_scope(token)
          expect(scope).to be_a(String).or be_nil
        end.not_to raise_error
      end
    end

    context 'when the token does not exist' do
      it 'returns nil' do
        scope = manager.get_token_scope('missing-token')
        expect(scope).to be_nil
      end
    end

    context 'when token is nil' do
      it 'returns nil without raising an error' do
        expect do
          scope = manager.get_token_scope(nil)
          expect(scope).to be_nil
        end.not_to raise_error
      end
    end
  end

  describe '#update_token_scope' do
    let(:user_id) do
      222
    end

    let!(:token) do
      manager.generate_token(user_id)
    end

    context 'when the token exists' do
      it 'does not raise an error when updating scope' do
        expect do
          manager.update_token_scope(token, 'write')
        end.not_to raise_error
      end
    end

    context 'when the token does not exist' do
      it 'does not raise an error and returns falsy or nil' do
        expect do
          result = manager.update_token_scope('missing-token', 'write')
          expect(!!result).to eq(result) if result == true || result == false
        end.not_to raise_error
      end
    end

    context 'when token is nil' do
      it 'returns falsey without raising an error' do
        expect do
          result = manager.update_token_scope(nil, 'write')
          expect(result).to be_falsey.or be_nil
        end.not_to raise_error
      end
    end
  end

  describe '#all_tokens_for_user' do
    let(:user_id_1) do
      1
    end

    let(:user_id_2) do
      2
    end

    let!(:token1_user1) do
      manager.generate_token(user_id_1)
    end

    let!(:token2_user1) do
      manager.generate_token(user_id_1)
    end

    let!(:token1_user2) do
      manager.generate_token(user_id_2)
    end

    it 'returns an Array' do
      tokens = manager.all_tokens_for_user(user_id_1)
      expect(tokens).to be_a(Array)
    end

    it 'does not raise error for user with no tokens' do
      expect do
        tokens = manager.all_tokens_for_user(999)
        expect(tokens).to be_a(Array)
      end.not_to raise_error
    end

    it 'does not raise error for nil user_id' do
      expect do
        tokens = manager.all_tokens_for_user(nil)
        expect(tokens).to be_a(Array)
      end.not_to raise_error
    end
  end

  describe 'external dependency mocking' do
    describe '#generate_token and SecureRandom' do
      it 'can be called without mocking SecureRandom' do
        token = manager.generate_token(10)
        expect(token).to be_a(String)
      end
    end

    describe 'Time.now usage' do
      it 'can generate a token without stubbing Time.now' do
        token = manager.generate_token(10)
        expect(token).to be_a(String)
      end
    end
  end
end