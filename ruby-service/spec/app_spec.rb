require 'rails_helper'
# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../app/app'

RSpec.describe PolyglotAPI do
  include Rack::Test::Methods

  def app
    PolyglotAPI
  end

  describe 'GET /health' do
    it 'returns healthy status' do
      get '/health'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['status']).to eq('healthy')
    end
  end

  describe 'POST /analyze' do
    it 'accepts valid content' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'language' => 'python', 'lines' => ['def test'] })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 85.0, 'issues' => [] })

      post '/analyze', { content: 'def test(): pass', path: 'test.py' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response).to have_key('summary')
    end
  end

  describe 'GET /status' do
    let(:go_url) { 'http://go-service' }
    let(:python_url) { 'http://python-service' }

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(
        double(
          go_service_url: go_url,
          python_service_url: python_url
        )
      )
      allow_any_instance_of(PolyglotAPI).to receive(:check_service_health).with(go_url)
        .and_return({ status: 'healthy' })
      allow_any_instance_of(PolyglotAPI).to receive(:check_service_health).with(python_url)
        .and_return({ status: 'unhealthy' })
    end

    it 'returns status for all services' do
      get '/status'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['services']['ruby']['status']).to eq('healthy')
      expect(json_response['services']['go']['status']).to eq('healthy')
      expect(json_response['services']['python']['status']).to eq('unhealthy')
    end
  end

  describe 'POST /analyze full behavior' do
    let(:content) { 'def test(): pass' }
    let(:path) { 'test.py' }
    let(:request_body) { { content: content, path: path }.to_json }
    let(:cache) { instance_double('RequestCache') }
    let(:analytics) { instance_double('AnalyticsTracker') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        cache: cache,
        analytics: analytics,
        token_manager: token_manager,
        go_service_url: 'http://go',
        python_service_url: 'http://py'
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(cache).to receive(:get).and_return(nil)
      allow(cache).to receive(:set)
      allow(analytics).to receive(:track_event)
      allow(token_manager).to receive(:verify_token).and_return(nil)
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'language' => 'python', 'lines' => ['def test'] })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 90.0, 'issues' => [] })
    end

    context 'when content is missing' do
      it 'returns 400 with error' do
        post '/analyze', {}.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing content')
      end
    end

    context 'when cache has stored result' do
      it 'returns cached result without calling services' do
        cached_result = { 'cached' => true }
        allow(cache).to receive(:get).and_return(cached_result)
        expect_any_instance_of(PolyglotAPI).not_to receive(:call_go_service)
        expect_any_instance_of(PolyglotAPI).not_to receive(:call_python_service)

        post '/analyze', request_body, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['cached']).to eq(true)
      end
    end

    context 'when user is authenticated' do
      it 'tracks analytics event' do
        allow(token_manager).to receive(:verify_token).and_return('user-123')
        header 'Authorization', 'Bearer token-123'

        expect(analytics).to receive(:track_event).with(
          'user-123',
          'code_analysis',
          hash_including(language: 'python', score: 90.0)
        )

        post '/analyze', request_body, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'POST /diff' do
    before do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'diff' => ['+ new line'] })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 80.0, 'issues' => [] })
    end

    context 'with valid payload' do
      it 'returns diff and new review' do
        payload = {
          old_content: "old",
          new_content: "new"
        }.to_json

        post '/diff', payload, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['diff']).to be_a(Hash)
        expect(json_response['new_code_review']).to be_a(Hash)
      end
    end

    context 'with missing fields' do
      it 'returns 400 when old_content is missing' do
        payload = { new_content: 'new' }.to_json
        post '/diff', payload, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing old_content or new_content')
      end
    end
  end

  describe 'POST /metrics' do
    before do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'complexity' => 1 })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 90.0, 'issues' => [] })
    end

    context 'with valid payload' do
      it 'returns metrics, review, and overall_quality' do
        payload = { content: 'some code' }.to_json
        post '/metrics', payload, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['metrics']).to be_a(Hash)
        expect(json_response['review']).to be_a(Hash)
        expect(json_response).to have_key('overall_quality')
      end
    end

    context 'with missing content' do
      it 'returns 400' do
        post '/metrics', {}.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing content')
      end
    end
  end

  describe 'POST /auth/session' do
    let(:session_store) { instance_double('SessionStore') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        session_store: session_store,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(session_store).to receive(:create).and_return('session-token')
      allow(token_manager).to receive(:generate_token).and_return('api-token')
    end

    context 'with valid JSON and user_id' do
      it 'creates session and returns tokens' do
        payload = { user_id: 'user-1', role: 'admin' }.to_json
        post '/auth/session', payload, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['session_token']).to eq('session-token')
        expect(json_response['api_token']).to eq('api-token')
      end
    end

    context 'with invalid JSON' do
      it 'returns 400 invalid JSON' do
        post '/auth/session', '{invalid}', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Invalid JSON')
      end
    end

    context 'with missing user_id' do
      it 'returns 400 missing user_id' do
        post '/auth/session', { role: 'admin' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing user_id')
      end
    end
  end

  describe 'DELETE /auth/session' do
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('user-1')
      allow(token_manager).to receive(:revoke_token)
    end

    it 'revokes token and returns success' do
      header 'Authorization', 'Bearer token-1'
      delete '/auth/session'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['success']).to eq(true)
      expect(token_manager).to have_received(:revoke_token).with('token-1')
    end

    it 'returns 401 when unauthorized' do
      allow(token_manager).to receive(:verify_token).and_raise(StandardError.new('bad token'))
      header 'Authorization', 'Bearer bad'
      delete '/auth/session'
      expect(last_response.status).to eq(401)
    end
  end

  describe 'GET /analytics/user/:user_id' do
    let(:analytics) { instance_double('AnalyticsTracker') }
    let(:authz) { instance_double('AuthorizationManager') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        analytics: analytics,
        authz: authz,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('admin-user')
      allow(token_manager).to receive(:get_token_scope).and_return('admin')
      allow(authz).to receive(:can_perform?).with('admin', 'read').and_return(true)
      allow(analytics).to receive(:get_user_events).and_return([{ 'event' => 'code_analysis' }])
      allow(analytics).to receive(:compute_user_score).and_return(88.5)
    end

    it 'returns user analytics when authorized' do
      header 'Authorization', 'Bearer token'
      get '/analytics/user/user-1'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['events']).to be_an(Array)
      expect(json_response['average_score']).to eq(88.5)
    end

    it 'returns 403 when permission denied' do
      allow(authz).to receive(:can_perform?).with('admin', 'read').and_return(false)
      header 'Authorization', 'Bearer token'
      get '/analytics/user/user-1'
      expect(last_response.status).to eq(403)
    end
  end

  describe 'POST /analytics/event' do
    let(:analytics) { instance_double('AnalyticsTracker') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        analytics: analytics,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('user-1')
      allow(analytics).to receive(:track_event)
    end

    it 'tracks event when authorized and valid payload' do
      header 'Authorization', 'Bearer token'
      payload = { event_type: 'custom_event', data: { foo: 'bar' } }.to_json
      post '/analytics/event', payload, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['success']).to eq(true)
      expect(analytics).to have_received(:track_event).with('user-1', 'custom_event', hash_including('foo' => 'bar'))
    end

    it 'returns 400 for invalid JSON' do
      header 'Authorization', 'Bearer token'
      post '/analytics/event', '{invalid', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Invalid JSON')
    end

    it 'returns 400 when event_type missing' do
      header 'Authorization', 'Bearer token'
      post '/analytics/event', { data: {} }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing event_type')
    end
  end

  describe 'GET /analytics/events' do
    let(:analytics) { instance_double('AnalyticsTracker') }
    let(:authz) { instance_double('AuthorizationManager') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        analytics: analytics,
        authz: authz,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('admin-user')
      allow(token_manager).to receive(:get_token_scope).and_return('admin')
      allow(authz).to receive(:can_perform?).with('admin', 'read').and_return(true)
    end

    it 'returns all events when no type specified' do
      allow(analytics).to receive(:get_all_events).and_return([{ 'event_type' => 'a' }, { 'event_type' => 'b' }])
      header 'Authorization', 'Bearer token'
      get '/analytics/events'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['events'].length).to eq(2)
      expect(json_response['count']).to eq(2)
    end

    it 'filters events by type when specified' do
      allow(analytics).to receive(:get_events_by_type).with('code_analysis')
        .and_return([{ 'event_type' => 'code_analysis' }])
      header 'Authorization', 'Bearer token'
      get '/analytics/events?type=code_analysis'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['events'].length).to eq(1)
      expect(json_response['events'].first['event_type']).to eq('code_analysis')
    end
  end

  describe 'POST /cache/invalidate' do
    let(:cache) { instance_double('RequestCache') }
    let(:authz) { instance_double('AuthorizationManager') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        cache: cache,
        authz: authz,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('admin-user')
      allow(token_manager).to receive(:get_token_scope).and_return('admin')
      allow(authz).to receive(:can_perform?).with('admin', 'write').and_return(true)
      allow(cache).to receive(:invalidate)
    end

    it 'invalidates cache when authorized' do
      header 'Authorization', 'Bearer token'
      payload = { key: 'value' }.to_json
      post '/cache/invalidate', payload, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['success']).to eq(true)
      expect(cache).to have_received(:invalidate).with(hash_including('key' => 'value'))
    end

    it 'returns 400 for invalid JSON' do
      header 'Authorization', 'Bearer token'
      post '/cache/invalidate', '{invalid', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Invalid JSON')
    end
  end

  describe 'GET /admin/sessions' do
    let(:session_store) { instance_double('SessionStore') }
    let(:authz) { instance_double('AuthorizationManager') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        session_store: session_store,
        authz: authz,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('admin-user')
      allow(token_manager).to receive(:get_token_scope).and_return('admin')
      allow(authz).to receive(:can_perform?).with('admin', 'manage_users').and_return(true)
      allow(session_store).to receive(:all_sessions).and_return([{ 'user_id' => 'u1' }])
    end

    it 'returns sessions when authorized' do
      header 'Authorization', 'Bearer token'
      get '/admin/sessions'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['sessions'].length).to eq(1)
      expect(json_response['count']).to eq(1)
    end
  end

  describe '#detect_language' do
    let(:instance) { app.new! }

    it 'detects go from .go extension' do
      expect(instance.send(:detect_language, 'main.go')).to eq('go')
    end

    it 'detects python from .py extension' do
      expect(instance.send(:detect_language, 'script.py')).to eq('python')
    end

    it 'detects ruby from .rb extension' do
      expect(instance.send(:detect_language, 'app.rb')).to eq('ruby')
    end

    it 'returns unknown for unsupported extensions' do
      expect(instance.send(:detect_language, 'file.unknown')).to eq('unknown')
    end

    it 'returns unknown when no extension' do
      expect(instance.send(:detect_language, 'README')).to eq('unknown')
    end
  end

  describe '#calculate_quality_score' do
    let(:instance) { app.new! }

    context 'when metrics or review are nil or have errors' do
      it 'returns 0.0 when metrics is nil' do
        expect(instance.send(:calculate_quality_score, nil, { 'score' => 80 })).to eq(0.0)
      end

      it 'returns 0.0 when review is nil' do
        expect(instance.send(:calculate_quality_score, { 'complexity' => 1 }, nil)).to eq(0.0)
      end

      it 'returns 0.0 when metrics has error' do
        expect(instance.send(:calculate_quality_score, { 'error' => 'oops' }, { 'score' => 80 })).to eq(0.0)
      end

      it 'returns 0.0 when review has error' do
        expect(instance.send(:calculate_quality_score, { 'complexity' => 1 }, { 'error' => 'oops' })).to eq(0.0)
      end
    end

    context 'with valid metrics and review' do
      it 'calculates score based on complexity and issues' do
        metrics = { 'complexity' => 2 }
        review = { 'score' => 90.0, 'issues' => [1, 2] }
        score = instance.send(:calculate_quality_score, metrics, review)
        expect(score).to be_a(Float)
        expect(score).to be >= 0
        expect(score).to be <= 100
      end

      it 'clamps score to 0 when very low' do
        metrics = { 'complexity' => 100 }
        review = { 'score' => 0.0, 'issues' => Array.new(100) { 1 } }
        score = instance.send(:calculate_quality_score, metrics, review)
        expect(score).to eq(0)
      end

      it 'clamps score to 100 when very high' do
        metrics = { 'complexity' => 0 }
        review = { 'score' => 200.0, 'issues' => [] }
        score = instance.send(:calculate_quality_score, metrics, review)
        expect(score).to eq(100)
      end
    end
  end

  describe '#check_service_health' do
    let(:instance) { app.new! }

    it 'returns healthy when HTTP 200' do
      response = instance_double('HTTParty::Response', code: 200)
      allow(HTTParty).to receive(:get).and_return(response)
      result = instance.send(:check_service_health, 'http://service')
      expect(result[:status]).to eq('healthy')
    end

    it 'returns unhealthy when non-200' do
      response = instance_double('HTTParty::Response', code: 500)
      allow(HTTParty).to receive(:get).and_return(response)
      result = instance.send(:check_service_health, 'http://service')
      expect(result[:status]).to eq('unhealthy')
    end

    it 'returns unreachable on exceptions' do
      allow(HTTParty).to receive(:get).and_raise(StandardError.new('timeout'))
      result = instance.send(:check_service_health, 'http://service')
      expect(result[:status]).to eq('unreachable')
      expect(result[:error]).to eq('timeout')
    end
  end

  describe '#call_go_service' do
    let(:instance) { app.new! }

    it 'posts data and parses JSON response' do
      response = instance_double('HTTParty::Response', body: { result: 'ok' }.to_json)
      allow(HTTParty).to receive(:post).and_return(response)
      allow(instance).to receive_message_chain(:settings, :go_service_url).and_return('http://go')
      result = instance.send(:call_go_service, '/endpoint', { a: 1 })
      expect(result['result']).to eq('ok')
    end

    it 'returns error hash on exception' do
      allow(HTTParty).to receive(:post).and_raise(StandardError.new('boom'))
      allow(instance).to receive_message_chain(:settings, :go_service_url).and_return('http://go')
      result = instance.send(:call_go_service, '/endpoint', { a: 1 })
      expect(result[:error]).to eq('boom')
    end
  end

  describe '#call_python_service' do
    let(:instance) { app.new! }

    it 'posts data and parses JSON response' do
      response = instance_double('HTTParty::Response', body: { result: 'ok' }.to_json)
      allow(HTTParty).to receive(:post).and_return(response)
      allow(instance).to receive_message_chain(:settings, :python_service_url).and_return('http://py')
      result = instance.send(:call_python_service, '/endpoint', { a: 1 })
      expect(result['result']).to eq('ok')
    end

    it 'returns error hash on exception' do
      allow(HTTParty).to receive(:post).and_raise(StandardError.new('boom'))
      allow(instance).to receive_message_chain(:settings, :python_service_url).and_return('http://py')
      result = instance.send(:call_python_service, '/endpoint', { a: 1 })
      expect(result[:error]).to eq('boom')
    end
  end

  describe '#get_authenticated_user_id' do
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        token_manager: token_manager
      )
    end

    let(:instance) do
      env = Rack::MockRequest.env_for('/', 'HTTP_AUTHORIZATION' => auth_header)
      app.new!(env)
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
    end

    context 'when Authorization header is missing' do
      let(:auth_header) { nil }

      it 'returns nil' do
        expect(instance.send(:get_authenticated_user_id)).to be_nil
      end
    end

    context 'when token is valid' do
      let(:auth_header) { 'Bearer good-token' }

      it 'returns user id from token manager' do
        allow(token_manager).to receive(:verify_token).with('good-token').and_return('user-1')
        expect(instance.send(:get_authenticated_user_id)).to eq('user-1')
      end
    end

    context 'when token verification raises error' do
      let(:auth_header) { 'Bearer bad-token' }

      it 'returns nil' do
        allow(token_manager).to receive(:verify_token).with('bad-token').and_raise(StandardError.new('invalid'))
        expect(instance.send(:get_authenticated_user_id)).to be_nil
      end
    end
  end

  describe '#require_auth' do
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
    end

    it 'returns user id when authenticated' do
      header 'Authorization', 'Bearer token'
      allow(token_manager).to receive(:verify_token).and_return('user-1')
      get '/health'
      instance = last_request.env['sinatra.route'].split.first == 'GET' ? app.new!(last_request.env) : app.new!
      allow(instance).to receive(:get_authenticated_user_id).and_return('user-1')
      expect(instance.send(:require_auth)).to eq('user-1')
    end
  end

  describe '#require_permission' do
    let(:authz) { instance_double('AuthorizationManager') }
    let(:token_manager) { instance_double('ApiTokenManager') }
    let(:settings_double) do
      double(
        authz: authz,
        token_manager: token_manager
      )
    end

    before do
      allow(PolyglotAPI).to receive(:settings).and_return(settings_double)
      allow(token_manager).to receive(:verify_token).and_return('user-1')
      allow(token_manager).to receive(:get_token_scope).and_return('admin')
    end

    it 'returns user id when permission granted' do
      allow(authz).to receive(:can_perform?).with('admin', 'read').and_return(true)
      header 'Authorization', 'Bearer token'
      get '/health'
      instance = app.new!(last_request.env)
      expect(instance.send(:require_permission, 'read')).to eq('user-1')
    end

    it 'halts with 403 when permission denied' do
      allow(authz).to receive(:can_perform?).with('admin', 'write').and_return(false)
      header 'Authorization', 'Bearer token'
      post '/analytics/event', { event_type: 'test' }.to_json, 'CONTENT_TYPE' => 'application/json'
      instance = app.new!(last_request.env)
      expect do
        instance.send(:require_permission, 'write')
      end.to raise_error(Sinatra::Halt)
    end
  end
end
