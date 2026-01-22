require 'rails_helper'
require_relative '../../app/services/session_store'
require 'spec_helper'

RSpec.describe SessionStore do
  let(:timeout_seconds) { 3600 }
  let(:store) { described_class.new(timeout_seconds: timeout_seconds) }
  let(:user_id) { 123 }
  let(:metadata) { { ip: '127.0.0.1', agent: 'RSpec' } }

  describe '#initialize' do
    it 'sets default timeout when not provided' do
      store_default = described_class.new
      token = store_default.create(user_id)
      expect(store_default.validate(token)).to eq(user_id)
    end

    it 'uses the provided timeout' do
      short_store = described_class.new(timeout_seconds: 1)
      token = short_store.create(user_id)
      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(short_store.validate(token)).to be_nil
    end

    it 'starts with no sessions' do
      expect(store.all_sessions).to eq({})
    end
  end

  describe '#create' do
    let(:token) { store.create(user_id, metadata) }

    it 'returns a token string' do
      expect(token).to be_a(String)
      expect(token).not_to be_empty
    end

    it 'stores a session with the given user_id and metadata' do
      token
      sessions = store.all_sessions
      expect(sessions[token]).not_to be_nil
      expect(sessions[token][:user_id]).to eq(user_id)
      expect(sessions[token][:metadata]).to eq(metadata)
      expect(sessions[token][:created_at]).to be_a(Time)
    end

    it 'generates unique tokens for multiple sessions of same user' do
      token1 = store.create(user_id, metadata)
      token2 = store.create(user_id, metadata)
      expect(token1).not_to eq(token2)
    end

    it 'generates unique tokens for different users' do
      token1 = store.create(1, metadata)
      token2 = store.create(2, metadata)
      expect(token1).not_to eq(token2)
    end

    context 'when metadata is not provided' do
      let(:token) { store.create(user_id) }

      it 'defaults metadata to an empty hash' do
        token
        sessions = store.all_sessions
        expect(sessions[token][:metadata]).to eq({})
      end
    end

    context 'token format' do
      it 'includes checksum and random parts separated by underscore' do
        token = store.create(user_id, metadata)
        checksum, random = token.split('_', 2)
        expect(checksum.length).to eq(16)
        expect(random.length).to eq(48)
      end
    end
  end

  describe '#validate' do
    let(:token) { store.create(user_id, metadata) }

    context 'when token exists and is not expired' do
      it 'returns the associated user_id' do
        expect(store.validate(token)).to eq(user_id)
      end

      it 'does not delete the session' do
        store.validate(token)
        expect(store.all_sessions[token]).not_to be_nil
      end
    end

    context 'when token does not exist' do
      it 'returns nil' do
        expect(store.validate('non-existent-token')).to be_nil
      end
    end

    context 'when session is expired' do
      let(:timeout_seconds) { 1 }

      it 'returns nil and deletes the session' do
        token
        created_at = Time.now
        allow(Time).to receive(:now).and_return(created_at, created_at + 2)
        expect(store.validate(token)).to be_nil
        expect(store.all_sessions[token]).to be_nil
      end
    end

    context 'edge cases' do
      it 'handles nil token gracefully' do
        expect(store.validate(nil)).to be_nil
      end

      it 'handles empty string token gracefully' do
        expect(store.validate('')).to be_nil
      end
    end
  end

  describe '#destroy' do
    let!(:token) { store.create(user_id, metadata) }

    it 'removes the session for the given token' do
      expect(store.all_sessions[token]).not.to be_nil
      store.destroy(token)
      expect(store.all_sessions[token]).to be_nil
    end

    it 'returns the deleted session data when present' do
      deleted = store.destroy(token)
      expect(deleted).to include(user_id: user_id, metadata: metadata)
    end

    it 'returns nil when token does not exist' do
      store.destroy(token)
      expect(store.destroy(token)).to be_nil
      expect(store.destroy('unknown')).to be_nil
    end

    it 'handles nil token gracefully' do
      expect(store.destroy(nil)).to be_nil
    end
  end

  describe '#all_sessions' do
    let!(:token1) { store.create(1, ip: '1.1.1.1') }
    let!(:token2) { store.create(2, ip: '2.2.2.2') }

    it 'returns a duplicate of the internal sessions hash' do
      sessions = store.all_sessions
      expect(sessions[token1][:user_id]).to eq(1)
      expect(sessions[token2][:user_id]).to eq(2)
    end

    it 'does not allow external mutation of internal state' do
      sessions = store.all_sessions
      sessions.clear
      expect(store.all_sessions).not_to eq({})
    end
  end

  describe 'token generation and randomness' do
    before do
      allow(SecureRandom).to receive(:hex).and_call_original
      allow(Digest::SHA256).to receive(:hexdigest).and_call_original
    end

    it 'uses SecureRandom.hex with length 24' do
      store.create(user_id, metadata)
      expect(SecureRandom).to have_received(:hex).with(24)
    end

    it 'uses Digest::SHA256 to compute checksum' do
      store.create(user_id, metadata)
      expect(Digest::SHA256).to have_received(:hexdigest).at_least(:once)
    end

    it 'increments internal counter for each token to improve uniqueness' do
      store.create(1)
      store.create(2)
      expect(Digest::SHA256).to have_received(:hexdigest).twice
    end
  end

  describe 'expiration behavior (time-based edge cases)' do
    let(:timeout_seconds) { 10 }
    let(:fixed_time) { Time.now }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    it 'treats a session exactly at timeout boundary as expired' do
      token = store.create(user_id)
      allow(Time).to receive(:now).and_return(fixed_time + timeout_seconds + 0.000001)
      expect(store.validate(token)).to be_nil
    end

    it 'keeps session valid right before timeout' do
      token = store.create(user_id)
      allow(Time).to receive(:now).and_return(fixed_time + timeout_seconds - 0.1)
      expect(store.validate(token)).to eq(user_id)
    end
  end

  describe 'error handling for external dependencies' do
    let(:user_id) { 999 }

    context 'when SecureRandom raises an error' do
      before do
        allow(SecureRandom).to receive(:hex).and_raise(StandardError.new('rng failure'))
      end

      it 'propagates the error from create' do
        expect do
          store.create(user_id)
        end.to raise_error(StandardError, 'rng failure')
      end
    end

    context 'when Digest::SHA256 raises an error' do
      before do
        allow(Digest::SHA256).to receive(:hexdigest).and_raise(StandardError.new('digest failure'))
      end

      it 'propagates the error from create' do
        expect do
          store.create(user_id)
        end.to raise_error(StandardError, 'digest failure')
      end
    end
  end
end
