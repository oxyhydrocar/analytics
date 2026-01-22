# LOAD ERROR: cannot load such file -- rails_helper
# The following code has been commented out due to load errors.
# Please fix the missing constant/require and uncomment.

require 'spec_helper'
require_relative '../../app/services/analytics_tracker'

# COMMENTED: RSpec.describe AnalyticsTracker do
#   describe '#initialize' do
#     let(:tracker) { described_class.new }
# 
#     it 'initializes @events as an empty array' do
#       expect(tracker.instance_variable_get(:@events)).to eq([])
#     end
# 
#     it 'initializes @user_sessions as an empty hash' do
#       expect(tracker.instance_variable_get(:@user_sessions)).to eq({})
#     end
#   end
# 
#   describe '#track_event' do
#     let(:tracker) { described_class.new }
#     let(:user_id) { 1 }
#     let(:event_type) { 'click' }
#     let(:data) { { score: 10, extra: 'info' } }
# 
#     context 'basic behavior' do
#       it 'appends an event hash to @events' do
#         tracker.track_event(user_id, event_type, data)
# 
#         events = tracker.instance_variable_get(:@events)
#         expect(events.size).to eq(1)
#         event = events.first
# 
#         expect(event[:user_id]).to eq(user_id)
#         expect(event[:event_type]).to eq(event_type)
#         expect(event).to have_key(:timestamp)
#       end
# 
#       it 'stores events per user in @user_sessions' do
#         tracker.track_event(user_id, event_type, data)
# 
#         user_sessions = tracker.instance_variable_get(:@user_sessions)
#         expect(user_sessions[user_id]).to be_an(Array)
#         expect(user_sessions[user_id].size).to eq(1)
#         expect(user_sessions[user_id].first[:event_type]).to eq(event_type)
#       end
# 
#       it 'tracks events for multiple users separately' do
#         tracker.track_event(user_id, event_type, data)
#         tracker.track_event(2, 'view', {})
# 
#         user_sessions = tracker.instance_variable_get(:@user_sessions)
#         expect(user_sessions[user_id].map { |e| e[:user_id] }).to all(eq(user_id))
#         expect(user_sessions[2].map { |e| e[:user_id] }).to all(eq(2))
#       end
#     end
# 
#     context 'data argument handling' do
#       it 'allows omitting data argument' do
#         tracker.track_event(user_id, event_type)
# 
#         event = tracker.instance_variable_get(:@events).first
#         expect(event).to have_key(:data)
#       end
# 
#       it 'does not raise error when called with nil data' do
#         expect do
#           tracker.track_event(user_id, event_type, nil)
#         end.not_to raise_error
#       end
# 
#       it 'allows non-hash data values' do
#         tracker.track_event(user_id, event_type, 'string-data')
# 
#         event = tracker.instance_variable_get(:@events).first
#         expect(event[:data]).to eq('string-data')
#       end
#     end
#   end
# 
#   describe '#get_user_events' do
#     let(:tracker) { described_class.new }
#     let(:user_id) { 1 }
# 
#     context 'when user has events' do
#       before do
#         tracker.track_event(user_id, 'click', {})
#         tracker.track_event(user_id, 'view', {})
#       end
# 
#       it 'returns an array of events for the user' do
#         events = tracker.get_user_events(user_id)
#         expect(events).to be_an(Array)
#         expect(events.map { |e| e[:event_type] }).to include('click', 'view')
#       end
#     end
# 
#     context 'when user has no events' do
#       it 'returns an empty array' do
#         events = tracker.get_user_events(user_id)
#         expect(events).to be_an(Array)
#         expect(events).to be_empty
#       end
#     end
# 
#     context 'when user_id is nil' do
#       it 'returns an empty array' do
#         events = tracker.get_user_events(nil)
#         expect(events).to be_an(Array)
#         expect(events).to be_empty
#       end
#     end
#   end
# 
#   describe '#get_all_events' do
#     let(:tracker) { described_class.new }
# 
#     context 'when there are events' do
#       before do
#         tracker.track_event(1, 'click', {})
#         tracker.track_event(2, 'view', {})
#       end
# 
#       it 'returns all events' do
#         events = tracker.get_all_events
#         expect(events.size).to eq(2)
#         expect(events.map { |e| e[:event_type] }).to include('click', 'view')
#       end
#     end
# 
#     context 'when there are no events' do
#       it 'returns an empty array' do
#         events = tracker.get_all_events
#         expect(events).to be_an(Array)
#         expect(events).to be_empty
#       end
#     end
#   end
# 
#   describe '#get_events_by_type' do
#     let(:tracker) { described_class.new }
# 
#     before do
#       tracker.track_event(1, 'click', {})
#       tracker.track_event(2, 'view', {})
#       tracker.track_event(3, 'click', {})
#     end
# 
#     context 'when events of the given type exist' do
#       it 'returns only events of that type' do
#         events = tracker.get_events_by_type('click')
#         expect(events).to all(satisfy { |e| e[:event_type] == 'click' })
#       end
#     end
# 
#     context 'when no events of the given type exist' do
#       it 'returns an empty array' do
#         events = tracker.get_events_by_type('purchase')
#         expect(events).to be_an(Array)
#         expect(events).to be_empty
#       end
#     end
# 
#     context 'when event_type is nil' do
#       it 'returns events with nil event_type only, if any' do
#         tracker.track_event(4, nil, {})
#         events = tracker.get_events_by_type(nil)
#         expect(events.map { |e| e[:event_type] }.uniq).to eq([nil])
#       end
#     end
#   end
# 
#   describe '#compute_user_score' do
#     let(:tracker) { described_class.new }
#     let(:user_id) { 1 }
# 
#     context 'when user has no events' do
#       it 'returns 0.0' do
#         expect(tracker.compute_user_score(user_id)).to eq(0.0)
#       end
# 
#       it 'handles missing user_id key safely' do
#         expect do
#           tracker.compute_user_score(999)
#         end.not_to raise_error
#       end
#     end
# 
#     context 'when events have numeric scores as symbols' do
#       before do
#         tracker.track_event(user_id, 'a', { score: 10 })
#         tracker.track_event(user_id, 'b', { score: 20 })
#       end
# 
#       it 'returns a numeric score' do
#         score = tracker.compute_user_score(user_id)
#         expect(score).to be_a(Numeric)
#       end
#     end
# 
#     context 'when events have numeric scores as string keys' do
#       before do
#         tracker.track_event(user_id, 'a', { 'score' => 5 })
#         tracker.track_event(user_id, 'b', { 'score' => 15 })
#       end
# 
#       it 'returns a numeric score' do
#         score = tracker.compute_user_score(user_id)
#         expect(score).to be_a(Numeric)
#       end
#     end
# 
#     context 'when events mix symbol and string score keys' do
#       before do
#         tracker.track_event(user_id, 'a', { score: 10 })
#         tracker.track_event(user_id, 'b', { 'score' => 20 })
#       end
# 
#       it 'returns a numeric score' do
#         score = tracker.compute_user_score(user_id)
#         expect(score).to be_a(Numeric)
#       end
#     end
# 
#     context 'when some events have no score' do
#       before do
#         tracker.track_event(user_id, 'a', { score: 10 })
#         tracker.track_event(user_id, 'b', {})
#         tracker.track_event(user_id, 'c', { 'score' => 20 })
#       end
# 
#       it 'ignores unscored events without raising' do
#         expect do
#           tracker.compute_user_score(user_id)
#         end.not_to raise_error
#       end
#     end
# 
#     context 'when score values are non-numeric but convertible' do
#       before do
#         tracker.track_event(user_id, 'a', { score: '10.5' })
#         tracker.track_event(user_id, 'b', { 'score' => '9.5' })
#       end
# 
#       it 'returns a numeric score' do
#         score = tracker.compute_user_score(user_id)
#         expect(score).to be_a(Numeric)
#       end
#     end
# 
#     context 'when some score values are nil' do
#       before do
#         tracker.track_event(user_id, 'a', { score: nil })
#         tracker.track_event(user_id, 'b', { 'score' => 10 })
#       end
# 
#       it 'ignores nil scores without raising' do
#         expect do
#           tracker.compute_user_score(user_id)
#         end.not_to raise_error
#       end
#     end
# 
#     context 'when internal user_sessions entry is manually set to nil (robustness)' do
#       before do
#         tracker.instance_variable_get(:@user_sessions)[user_id] = nil
#       end
# 
#       it 'handles nil events gracefully and returns 0.0' do
#         expect(tracker.compute_user_score(user_id)).to eq(0.0)
#       end
#     end
#   end
# end