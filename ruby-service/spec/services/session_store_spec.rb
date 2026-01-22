require 'rails_helper'
require_relative '../../app/services/session_store'
require 'spec_helper'

RSpec.describe SessionStore do
  describe '#initialize' do
    context 'with default timeout' do
      let(:store) do
        described_class.new
      end

      it 'sets default timeout to 3600 seconds' do
        timeout = store.instance_variable_get(:@timeout)
        expect(timeout).to eq(3600)
      end

      it 'initializes sessions as an empty hash' do
        sessions = store.instance_variable_get(:@sessions)
        expect(sessions).to eq({})
      end

      it 'initializes counter to 0' do
        counter = store.instance_variable_get(:@counter)
        expect(counter).to eq(0)
      end
    end

    context 'with custom timeout' do
      let(:custom_timeout) do
        120
      end

      let(:store) do
        described_class.new(timeout_seconds: custom_timeout)
      end

      it 'uses the provided timeout' do
        timeout = store.instance_variable_get(:@timeout)
        expect(timeout).to eq(custom_timeout)
      end
    end
  end

  describe '#create' do
    let(:timeout) do
      3600
    end

    let(:store) do
      described_class.new(timeout_seconds: timeout)
    end

    let(:user_id) do
      123
    end

    let(:metadata) do
      { role: 'admin', ip: '127.0.0.1' }
    end

    let(:fixed_time) do
      Time.utc(2024, 1, 1, 12, 0, 0)
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
      allow(SecureRandom).to receive(:hex).and_return('a' * 48)
    end

    it 'returns a token string' do
      token = store.create(user_id, metadata)
      expect(token).to be_a(String)
      expect(token).not_to be_empty
    end

    it 'stores the session with correct user_id and metadata' do
      token = store.create(user_id, metadata)
      sessions = store.instance_variable_get(:@sessions)
      expect(sessions[token]).to include(
        user_id: user_id,
        metadata: metadata
      )
    end

    it 'stores the session with the current time as created_at' do
      token = store.create(user_id, metadata)
      sessions = store.instance_variable_get(:@sessions)
      expect(sessions[token][:created_at]).to eq(fixed_time)
    end

    it 'generates different tokens for different users' do
      allow(SecureRandom).to receive(:hex).and_return('a' * 48, 'b' * 48)
      token1 = store.create(1)
      token2 = store.create(2)
      expect(token1).not_to eq(token2)
    end

    it 'generates different tokens for same user on multiple calls' do
      allow(SecureRandom).to receive(:hex).and_return('a' * 48, 'b' * 48)
      token1 = store.create(user_id)
      token2 = store.create(user_id)
      expect(token1).not_to eq(token2)
    end

    it 'increments the internal counter for each token' do
      store.create(user_id)
      store.create(user_id)
      counter = store.instance_variable_get(:@counter)
      expect(counter).to eq(2)
    end

    it 'uses SHA256 checksum in the token' do
      token = store.create(user_id)
      checksum, random = token.split('_')
      expect(checksum.length).to eq(16)
      expect(random.length).to eq(48)
    end

    context 'when metadata is not provided' do
      it 'stores an empty hash as metadata' do
        token = store.create(user_id)
        sessions = store.instance_variable_get(:@sessions)
        expect(sessions[token][:metadata]).to eq({})
      end
    end
  end

  describe '#validate' do
    let(:timeout) do
      3600
    end

    let(:store) do
      described_class.new(timeout_seconds: timeout)
    end

    let(:user_id) do
      123
    end

    let(:created_time) do
      Time.utc(2024, 1, 1, 12, 0, 0)
    end

    let(:token) do
      store.create(user_id)
    end

    before do
      allow(Time).to receive(:now).and_return(created_time)
      allow(SecureRandom).to receive(:hex).and_return('a' * 48)
      token
    end

    context 'when token exists and is not expired' do
      before do
        allow(Time).to receive(:now).and_return(created_time + 100)
      end

      it 'returns the associated user_id' do
        result = store.validate(token)
        expect(result).to eq(user_id)
      end

      it 'does not remove the session' do
        store.validate(token)
        sessions = store.instance_variable_get(:@sessions)
        expect(sessions).to have_key(token)
      end
    end

    context 'when token does not exist' do
      it 'returns nil' do
        result = store.validate('nonexistent_token')
        expect(result).to be_nil
      end
    end

    context 'when token is expired' do
      before do
        allow(Time).to receive(:now).and_return(created_time + timeout + 1)
      end

      it 'returns nil' do
        result = store.validate(token)
        expect(result).to be_nil
      end

      it 'removes the session from the store' do
        store.validate(token)
        sessions = store.instance_variable_get(:@sessions)
        expect(sessions).not_to have_key(token)
      end
    end

    context 'when token is exactly at timeout boundary' do
      before do
        allow(Time).to receive(:now).and_return(created_time + timeout)
      end

      it 'treats the session as valid' do
        result = store.validate(token)
        expect(result).to eq(user_id)
      end
    end

    context 'error handling' do
      it 'does not raise an error when session data is malformed' do
        sessions = store.instance_variable_get(:@sessions)
        sessions[token] = {}
        store.instance_variable_set(:@sessions, sessions)

        expect do
          store.validate(token)
        end.not_to raise_error
      end
    end
  end

  describe '#destroy' do
    let(:store) do
      described_class.new
    end

    let(:user_id) do
      123
    end

    let!(:token) do
      allow(SecureRandom).to receive(:hex).and_return('a' * 48)
      store.create(user_id)
    end

    it 'removes the session from the store' do
      expect do
        store.destroy(token)
      end.to change { store.instance_variable_get(:@sessions).keys.include?(token) }.from(true).to(false)
    end

    it 'returns the removed session data if it existed' do
      removed = store.destroy(token)
      expect(removed).to include(user_id: user_id)
    end

    it 'returns nil if the token does not exist' do
      result = store.destroy('nonexistent')
      expect(result).to be_nil
    end

    it 'is idempotent when called multiple times' do
      store.destroy(token)
      expect do
        store.destroy(token)
      end.not_to raise_error
    end
  end

  describe '#all_sessions' do
    let(:store) do
      described_class.new
    end

    let(:user_id_1) do
      1
    end

    let(:user_id_2) do
      2
    end

    let!(:token1) do
      allow(SecureRandom).to receive(:hex).and_return('a' * 48)
      store.create(user_id_1, foo: 'bar')
    end

    let!(:token2) do
      allow(SecureRandom).to receive(:hex).and_return('b' * 48)
      store.create(user_id_2, baz: 'qux')
    end

    it 'returns a hash of all current sessions' do
      sessions = store.all_sessions
      expect(sessions.keys).to match_array([token1, token2])
      expect(sessions[token1][:user_id]).to eq(user_id_1)
      expect(sessions[token2][:user_id]).to eq(user_id_2)
    end

    it 'returns a duplicate of the internal sessions hash' do
      sessions = store.all_sessions
      sessions[token1][:user_id] = 999

      internal_sessions = store.instance_variable_get(:@sessions)
      expect(internal_sessions[token1][:user_id]).to eq(user_id_1)
    end
  end

  describe 'private methods' do
    let(:store) do
      described_class.new
    end

    describe '#generate_token' do
      let(:user_id) do
        42
      end

      before do
        allow(SecureRandom).to receive(:hex).and_return('a' * 48)
      end

      it 'generates a token matching the checksum_random format' do
        token = store.send(:generate_token, user_id)
        parts = token.split('_')
        expect(parts.size).to eq(2)
        expect(parts.first.length).to eq(16)
        expect(parts.last.length).to eq(48)
      end

      it 'uses the counter in the checksum calculation' do
        token1 = store.send(:generate_token, user_id)
        token2 = store.send(:generate_token, user_id)
        expect(token1).not_to eq(token2)
      end
    end

    describe '#expired?' do
      let(:timeout) do
        100
      end

      let(:store) do
        described_class.new(timeout_seconds: timeout)
      end

      let(:created_time) do
        Time.utc(2024, 1, 1, 12, 0, 0)
      end

      let(:session) do
        { created_at: created_time }
      end

      before do
        allow(Time).to receive(:now).and_return(created_time + offset)
      end

      context 'when session is within timeout' do
        let(:offset) do
          50
        end

        it 'returns false' do
          expect(store.send(:expired?, session)).to be(false)
        end
      end

      context 'when session is exactly at timeout' do
        let(:offset) do
          timeout
        end

        it 'returns false' do
          expect(store.send(:expired?, session)).to be(false)
        end
      end

      context 'when session exceeds timeout' do
        let(:offset) do
          timeout + 1
        end

        it 'returns true' do
          expect(store.send(:expired?, session)).to be(true)
        end
      end

      context 'when created_at is nil (malformed session)' do
        let(:session) do
          {}
        end

        let(:offset) do
          0
        end

        it 'raises an error due to subtraction from nil' do
          expect do
            store.send(:expired?, session)
          end.to raise_error(NoMethodError)
        end
      end
    end
  end
end
