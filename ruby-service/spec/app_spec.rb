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

    context 'when content is missing' do
      it 'returns 400 with error message' do
        post '/analyze', {}.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing content')
      end
    end

    context 'when request body is invalid JSON' do
      it 'falls back to params parsing' do
        allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
          .and_return({ 'language' => 'ruby', 'lines' => ['puts 1'] })
        allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
          .and_return({ 'score' => 90.0, 'issues' => [] })

        post '/analyze?content=test&path=test.rb', 'invalid-json', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['summary']['language']).to eq('ruby')
      end
    end

    context 'when result is cached' do
      let(:cache_double) { instance_double(RequestCache) }

      it 'returns cached response without calling services' do
        allow(PolyglotAPI).to receive(:settings).and_call_original
        allow(PolyglotAPI.settings).to receive(:cache).and_return(cache_double)

        request_data = { 'content' => 'code', 'path' => 'file.rb' }
        cached_result = { 'cached' => true }

        allow(cache_double).to receive(:get).with(request_data).and_return(cached_result)

        expect_any_instance_of(PolyglotAPI).not_to receive(:call_go_service)
        expect_any_instance_of(PolyglotAPI).not_to receive(:call_python_service)

        post '/analyze', request_data.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['cached']).to eq(true)
      end
    end

    context 'when user is authenticated' do
      let(:analytics_double) { instance_double(AnalyticsTracker) }
      let(:token_manager_double) { instance_double(ApiTokenManager) }
      let(:token) { 'valid-token' }

      it 'tracks analytics event' do
        allow(PolyglotAPI).to receive(:settings).and_call_original
        allow(PolyglotAPI.settings).to receive(:analytics).and_return(analytics_double)
        allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)

        allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
          .and_return({ 'language' => 'python', 'lines' => ['def test'] })
        allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
          .and_return({ 'score' => 80.0, 'issues' => [] })

        expect(token_manager_double).to receive(:verify_token).with(token).and_return('user-1')
        expect(analytics_double).to receive(:track_event).with('user-1', 'code_analysis', hash_including(:language, :score))

        header 'Authorization', "Bearer #{token}"
        post '/analyze', { content: 'def test(): pass', path: 'test.py' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'when user has invalid token' do
      let(:token_manager_double) { instance_double(ApiTokenManager) }
      let(:token) { 'invalid-token' }

      it 'does not raise and skips analytics' do
        allow(PolyglotAPI).to receive(:settings).and_call_original
        allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)

        allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
          .and_return({ 'language' => 'python', 'lines' => ['def test'] })
        allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
          .and_return({ 'score' => 80.0, 'issues' => [] })

        allow(token_manager_double).to receive(:verify_token).with(token).and_raise(StandardError.new('bad token'))

        header 'Authorization', "Bearer #{token}"
        post '/analyze', { content: 'def test(): pass', path: 'test.py' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'POST /diff' do
    let(:old_content) { 'old code' }
    let(:new_content) { 'new code' }

    context 'with valid payload' do
      it 'returns diff and new review' do
        allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
          .with('/diff', hash_including(:old_content, :new_content))
          .and_return({ 'changes' => [] })
        allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
          .with('/review', hash_including(:content))
          .and_return({ 'score' => 70.0 })

        post '/diff', { old_content: old_content, new_content: new_content }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response).to have_key('diff')
        expect(json_response).to have_key('new_code_review')
      end
    end

    context 'when contents are missing' do
      it 'returns 400 when old_content missing' do
        post '/diff', { new_content: new_content }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing old_content or new_content')
      end

      it 'returns 400 when new_content missing' do
        post '/diff', { old_content: old_content }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing old_content or new_content')
      end
    end
  end

  describe 'POST /metrics' do
    let(:content) { 'some code' }

    context 'with valid content' do
      it 'returns metrics, review and overall_quality' do
        allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
          .with('/metrics', hash_including(:content))
          .and_return({ 'complexity' => 3 })
        allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
          .with('/review', hash_including(:content))
          .and_return({ 'score' => 80.0, 'issues' => [] })

        post '/metrics', { content: content }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response).to have_key('metrics')
        expect(json_response).to have_key('review')
        expect(json_response).to have_key('overall_quality')
      end
    end

    context 'when content is missing' do
      it 'returns 400 with error' do
        post '/metrics', {}.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing content')
      end
    end
  end

  describe 'GET /status' do
    let(:healthy_response) { instance_double(HTTParty::Response, code: 200, body: '{}') }
    let(:unhealthy_response) { instance_double(HTTParty::Response, code: 500, body: '{}') }

    it 'returns aggregated status for services' do
      allow(HTTParty).to receive(:get).and_return(healthy_response)

      get '/status'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['services']['ruby']['status']).to eq('healthy')
      expect(json_response['services']['go']).to have_key('status')
      expect(json_response['services']['python']).to have_key('status')
    end

    it 'marks service unhealthy when non-200' do
      allow(HTTParty).to receive(:get).and_return(unhealthy_response)

      get '/status'
      json_response = JSON.parse(last_response.body)
      expect(json_response['services']['go']['status']).to eq('unhealthy')
      expect(json_response['services']['python']['status']).to eq('unhealthy')
    end

    it 'marks service unreachable on exception' do
      allow(HTTParty).to receive(:get).and_raise(StandardError.new('timeout'))

      get '/status'
      json_response = JSON.parse(last_response.body)
      expect(json_response['services']['go']['status']).to eq('unreachable')
      expect(json_response['services']['python']['status']).to eq('unreachable')
      expect(json_response['services']['go']['error']).to eq('timeout')
    end
  end

  describe 'POST /auth/session' do
    let(:session_store_double) { instance_double(SessionStore) }
    let(:token_manager_double) { instance_double(ApiTokenManager) }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:session_store).and_return(session_store_double)
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with valid data' do
      it 'creates session and returns tokens' do
        expect(session_store_double).to receive(:create).with('user-1', hash_including(:role)).and_return('session-token')
        expect(token_manager_double).to receive(:generate_token).with('user-1', scope: 'admin').and_return('api-token')

        post '/auth/session', { user_id: 'user-1', role: 'admin' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['session_token']).to eq('session-token')
        expect(json_response['api_token']).to eq('api-token')
      end
    end

    context 'when role is missing' do
      it 'defaults role to viewer' do
        expect(session_store_double).to receive(:create).with('user-2', hash_including(role: 'viewer')).and_return('session-token-2')
        expect(token_manager_double).to receive(:generate_token).with('user-2', scope: 'viewer').and_return('api-token-2')

        post '/auth/session', { user_id: 'user-2' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'when user_id is missing' do
      it 'returns 400 error' do
        post '/auth/session', { role: 'admin' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing user_id')
      end
    end

    context 'when JSON is invalid' do
      it 'returns 400 invalid JSON error' do
        post '/auth/session', 'invalid-json', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Invalid JSON')
      end
    end
  end

  describe 'DELETE /auth/session' do
    let(:token_manager_double) { instance_double(ApiTokenManager) }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with valid auth' do
      it 'revokes token and returns success' do
        token = 'valid-token'
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('user-1')
        expect(token_manager_double).to receive(:revoke_token).with(token)

        header 'Authorization', "Bearer #{token}"
        delete '/auth/session'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['success']).to eq(true)
      end
    end

    context 'without auth' do
      it 'returns 401 unauthorized' do
        delete '/auth/session'
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'GET /analytics/user/:user_id' do
    let(:analytics_double) { instance_double(AnalyticsTracker) }
    let(:authz_double) { instance_double(AuthorizationManager) }
    let(:token_manager_double) { instance_double(ApiTokenManager) }
    let(:token) { 'valid-token' }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:analytics).and_return(analytics_double)
      allow(PolyglotAPI.settings).to receive(:authz).and_return(authz_double)
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with permission' do
      it 'returns user analytics' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('admin-user')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('admin')
        allow(authz_double).to receive(:can_perform?).with('admin', 'read').and_return(true)
        allow(analytics_double).to receive(:get_user_events).with('user-1').and_return([{ 'event' => 'code_analysis' }])
        allow(analytics_double).to receive(:compute_user_score).with('user-1').and_return(88.5)

        header 'Authorization', "Bearer #{token}"
        get '/analytics/user/user-1'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['events'].length).to eq(1)
        expect(json_response['average_score']).to eq(88.5)
      end
    end

    context 'without permission' do
      it 'returns 403 forbidden' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('viewer-user')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('viewer')
        allow(authz_double).to receive(:can_perform?).with('viewer', 'read').and_return(false)

        header 'Authorization', "Bearer #{token}"
        get '/analytics/user/user-1'
        expect(last_response.status).to eq(403)
      end
    end

    context 'without auth' do
      it 'returns 401 unauthorized' do
        get '/analytics/user/user-1'
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'POST /analytics/event' do
    let(:analytics_double) { instance_double(AnalyticsTracker) }
    let(:token_manager_double) { instance_double(ApiTokenManager) }
    let(:token) { 'valid-token' }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:analytics).and_return(analytics_double)
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with valid auth and data' do
      it 'tracks event and returns success' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('user-1')
        expect(analytics_double).to receive(:track_event).with('user-1', 'custom_event', hash_including('foo' => 'bar'))

        header 'Authorization', "Bearer #{token}"
        post '/analytics/event', { event_type: 'custom_event', data: { foo: 'bar' } }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['success']).to eq(true)
      end
    end

    context 'when event_type is missing' do
      it 'returns 400 error' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('user-1')

        header 'Authorization', "Bearer #{token}"
        post '/analytics/event', { data: { foo: 'bar' } }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Missing event_type')
      end
    end

    context 'when JSON is invalid' do
      it 'returns 400 invalid JSON' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('user-1')

        header 'Authorization', "Bearer #{token}"
        post '/analytics/event', 'invalid-json', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Invalid JSON')
      end
    end

    context 'without auth' do
      it 'returns 401 unauthorized' do
        post '/analytics/event', { event_type: 'custom_event' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'GET /analytics/events' do
    let(:analytics_double) { instance_double(AnalyticsTracker) }
    let(:authz_double) { instance_double(AuthorizationManager) }
    let(:token_manager_double) { instance_double(ApiTokenManager) }
    let(:token) { 'valid-token' }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:analytics).and_return(analytics_double)
      allow(PolyglotAPI.settings).to receive(:authz).and_return(authz_double)
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with read permission' do
      it 'returns all events when no type filter' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('admin')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('admin')
        allow(authz_double).to receive(:can_perform?).with('admin', 'read').and_return(true)
        allow(analytics_double).to receive(:get_all_events).and_return([{ 'type' => 'a' }, { 'type' => 'b' }])

        header 'Authorization', "Bearer #{token}"
        get '/analytics/events'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['count']).to eq(2)
      end

      it 'returns filtered events by type' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('admin')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('admin')
        allow(authz_double).to receive(:can_perform?).with('admin', 'read').and_return(true)
        allow(analytics_double).to receive(:get_events_by_type).with('code_analysis').and_return([{ 'type' => 'code_analysis' }])

        header 'Authorization', "Bearer #{token}"
        get '/analytics/events?type=code_analysis'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['count']).to eq(1)
      end
    end

    context 'without permission' do
      it 'returns 403 forbidden' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('viewer')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('viewer')
        allow(authz_double).to receive(:can_perform?).with('viewer', 'read').and_return(false)

        header 'Authorization', "Bearer #{token}"
        get '/analytics/events'
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'POST /cache/invalidate' do
    let(:cache_double) { instance_double(RequestCache) }
    let(:authz_double) { instance_double(AuthorizationManager) }
    let(:token_manager_double) { instance_double(ApiTokenManager) }
    let(:token) { 'valid-token' }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:cache).and_return(cache_double)
      allow(PolyglotAPI.settings).to receive(:authz).and_return(authz_double)
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with write permission' do
      it 'invalidates cache and returns success' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('admin')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('admin')
        allow(authz_double).to receive(:can_perform?).with('admin', 'write').and_return(true)
        expect(cache_double).to receive(:invalidate).with(hash_including('content' => 'code'))

        header 'Authorization', "Bearer #{token}"
        post '/cache/invalidate', { content: 'code' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['success']).to eq(true)
      end
    end

    context 'when JSON invalid' do
      it 'returns 400 error' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('admin')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('admin')
        allow(authz_double).to receive(:can_perform?).with('admin', 'write').and_return(true)

        header 'Authorization', "Bearer #{token}"
        post '/cache/invalidate', 'invalid-json', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
        json_response = JSON.parse(last_response.body)
        expect(json_response['error']).to eq('Invalid JSON')
      end
    end

    context 'without permission' do
      it 'returns 403 forbidden' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('viewer')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('viewer')
        allow(authz_double).to receive(:can_perform?).with('viewer', 'write').and_return(false)

        header 'Authorization', "Bearer #{token}"
        post '/cache/invalidate', { content: 'code' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'GET /admin/sessions' do
    let(:session_store_double) { instance_double(SessionStore) }
    let(:authz_double) { instance_double(AuthorizationManager) }
    let(:token_manager_double) { instance_double(ApiTokenManager) }
    let(:token) { 'valid-token' }

    before do
      allow(PolyglotAPI).to receive(:settings).and_call_original
      allow(PolyglotAPI.settings).to receive(:session_store).and_return(session_store_double)
      allow(PolyglotAPI.settings).to receive(:authz).and_return(authz_double)
      allow(PolyglotAPI.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    context 'with manage_users permission' do
      it 'returns sessions list' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('admin')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('admin')
        allow(authz_double).to receive(:can_perform?).with('admin', 'manage_users').and_return(true)
        allow(session_store_double).to receive(:all_sessions).and_return([{ 'id' => 's1' }])

        header 'Authorization', "Bearer #{token}"
        get '/admin/sessions'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['count']).to eq(1)
      end
    end

    context 'without permission' do
      it 'returns 403 forbidden' do
        allow(token_manager_double).to receive(:verify_token).with(token).and_return('viewer')
        allow(token_manager_double).to receive(:get_token_scope).with(token).and_return('viewer')
        allow(authz_double).to receive(:can_perform?).with('viewer', 'manage_users').and_return(false)

        header 'Authorization', "Bearer #{token}"
        get '/admin/sessions'
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe '#detect_language' do
    let(:instance) { app.new! }

    it 'detects go by .go extension' do
      expect(instance.send(:detect_language, 'main.go')).to eq('go')
    end

    it 'detects python by .py extension' do
      expect(instance.send(:detect_language, 'script.py')).to eq('python')
    end

    it 'detects ruby by .rb extension' do
      expect(instance.send(:detect_language, 'app.rb')).to eq('ruby')
    end

    it 'detects javascript by .js extension' do
      expect(instance.send(:detect_language, 'app.js')).to eq('javascript')
    end

    it 'detects typescript by .ts extension' do
      expect(instance.send(:detect_language, 'app.ts')).to eq('typescript')
    end

    it 'detects java by .java extension' do
      expect(instance.send(:detect_language, 'Main.java')).to eq('java')
    end

    it 'returns unknown for unsupported extension' do
      expect(instance.send(:detect_language, 'file.txt')).to eq('unknown')
    end

    it 'returns unknown when no extension' do
      expect(instance.send(:detect_language, 'Makefile')).to eq('unknown')
    end
  end

  describe '#calculate_quality_score' do
    let(:instance) { app.new! }

    context 'when metrics or review is nil or has errors' do
      it 'returns 0.0 when metrics is nil' do
        expect(instance.send(:calculate_quality_score, nil, { 'score' => 80 })).to eq(0.0)
      end

      it 'returns 0.0 when review is nil' do
        expect(instance.send(:calculate_quality_score, { 'complexity' => 1 }, nil)).to eq(0.0)
      end

      it 'returns 0.0 when metrics has error' do
        expect(instance.send(:calculate_quality_score, { 'error' => 'fail' }, { 'score' => 80 })).to eq(0.0)
      end

      it 'returns 0.0 when review has error' do
        expect(instance.send(:calculate_quality_score, { 'complexity' => 1 }, { 'error' => 'fail' })).to eq(0.0)
      end
    end

    context 'with valid metrics and review' do
      it 'calculates score with penalties and clamps to 0..100' do
        metrics = { 'complexity' => 2 }
        review = { 'score' => 80.0, 'issues' => [1, 2] }
        # base 0.8 -> 80
        # complexity_penalty = 0.2
        # issue_penalty = 1.0
        # final = 0.8 - 0.2 - 1.0 = -0.4 -> -40 -> clamped 0
        expect(instance.send(:calculate_quality_score, metrics, review)).to eq(0)
      end

      it 'returns 100 when above 100 after rounding and clamping' do
        metrics = { 'complexity' => 0 }
        review = { 'score' => 120.0, 'issues' => [] }
        expect(instance.send(:calculate_quality_score, metrics, review)).to eq(100)
      end

      it 'returns expected score for simple case' do
        metrics = { 'complexity' => 1 }
        review = { 'score' => 90.0, 'issues' => [] }
        # base 0.9 -> 90
        # penalty 0.1 -> 10
        # final 80
        expect(instance.send(:calculate_quality_score, metrics, review)).to eq(80)
      end
    end
  end

  describe '#call_go_service' do
    let(:instance) { app.new! }
    let(:response_double) { instance_double(HTTParty::Response, body: '{"ok":true}') }

    it 'posts to go service and parses JSON' do
      allow(instance.settings).to receive(:go_service_url).and_return('http://go-service')
      expect(HTTParty).to receive(:post).with(
        'http://go-service/parse',
        hash_including(
          :body,
          :headers,
          :timeout
        )
      ).and_return(response_double)

      result = instance.send(:call_go_service, '/parse', { foo: 'bar' })
      expect(result['ok']).to eq(true)
    end

    it 'returns error hash when exception occurs' do
      allow(instance.settings).to receive(:go_service_url).and_return('http://go-service')
      allow(HTTParty).to receive(:post).and_raise(StandardError.new('boom'))

      result = instance.send(:call_go_service, '/parse', { foo: 'bar' })
      expect(result['error']).to eq('boom')
    end
  end

  describe '#call_python_service' do
    let(:instance) { app.new! }
    let(:response_double) { instance_double(HTTParty::Response, body: '{"ok":true}') }

    it 'posts to python service and parses JSON' do
      allow(instance.settings).to receive(:python_service_url).and_return('http://py-service')
      expect(HTTParty).to receive(:post).with(
        'http://py-service/review',
        hash_including(
          :body,
          :headers,
          :timeout
        )
      ).and_return(response_double)

      result = instance.send(:call_python_service, '/review', { foo: 'bar' })
      expect(result['ok']).to eq(true)
    end

    it 'returns error hash when exception occurs' do
      allow(instance.settings).to receive(:python_service_url).and_return('http://py-service')
      allow(HTTParty).to receive(:post).and_raise(StandardError.new('py-boom'))

      result = instance.send(:call_python_service, '/review', { foo: 'bar' })
      expect(result['error']).to eq('py-boom')
    end
  end

  describe '#check_service_health' do
    let(:instance) { app.new! }
    let(:healthy_response) { instance_double(HTTParty::Response, code: 200) }
    let(:unhealthy_response) { instance_double(HTTParty::Response, code: 500) }

    it 'returns healthy when status code is 200' do
      allow(HTTParty).to receive(:get).and_return(healthy_response)
      result = instance.send(:check_service_health, 'http://svc')
      expect(result[:status]).to eq('healthy')
    end

    it 'returns unhealthy when status code is not 200' do
      allow(HTTParty).to receive(:get).and_return(unhealthy_response)
      result = instance.send(:check_service_health, 'http://svc')
      expect(result[:status]).to eq('unhealthy')
    end

    it 'returns unreachable when exception is raised' do
      allow(HTTParty).to receive(:get).and_raise(StandardError.new('timeout'))
      result = instance.send(:check_service_health, 'http://svc')
      expect(result[:status]).to eq('unreachable')
      expect(result[:error]).to eq('timeout')
    end
  end

  describe '#get_authenticated_user_id' do
    let(:instance) { app.new! }
    let(:token_manager_double) { instance_double(ApiTokenManager) }

    before do
      allow(instance.settings).to receive(:token_manager).and_return(token_manager_double)
    end

    it 'returns nil when no Authorization header' do
      env = { 'rack.input' => StringIO.new('') }
      status, headers, body = instance.call(env)
      expect(status).to be_a(Integer)

      allow(instance).to receive(:request).and_return(Rack::Request.new({}))
      result = instance.send(:get_authenticated_user_id)
      expect(result).to be_nil
    end

    it 'returns user id when token is valid' do
      env = { 'HTTP_AUTHORIZATION' => 'Bearer token-123', 'rack.input' => StringIO.new('') }
      allow(instance).to receive(:request).and_return(Rack::Request.new(env))

      expect(token_manager_double).to receive(:verify_token).with('token-123').and_return('user-1')

      result = instance.send(:get_authenticated_user_id)
      expect(result).to eq('user-1')
    end

    it 'returns nil when token verification raises' do
      env = { 'HTTP_AUTHORIZATION' => 'Bearer bad-token', 'rack.input' => StringIO.new('') }
      allow(instance).to receive(:request).and_return(Rack::Request.new(env))

      allow(token_manager_double).to receive(:verify_token).with('bad-token').and_raise(StandardError.new('invalid'))

      result = instance.send(:get_authenticated_user_id)
      expect(result).to be_nil
    end
  end
end
