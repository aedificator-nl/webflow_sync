# frozen_string_literal: true

require 'rails_helper'

module WebflowSync
  # rubocop:disable RSpec/MultipleMemoizedHelpers
  RSpec.describe WebflowSync::UpdateItemJob do
    let(:model_name) { 'articles' }
    let(:article) { create(:article, webflow_item_id: '653817458c993c9a49fc411b') }
    let(:mock_webflow_api) { instance_double(WebflowSync::Api, update_item: nil) }

    let(:sync_webflow_slug) { false }
    let(:webflow_site_id) { ENV.fetch('WEBFLOW_SITE_ID') }

    before(:each) do
      @old_sync_webflow_slug = WebflowSync.configuration.sync_webflow_slug
      @old_webflow_site_id = WebflowSync.configuration.webflow_site_id

      WebflowSync.configure do |config|
        config.sync_webflow_slug = sync_webflow_slug
        config.webflow_site_id = webflow_site_id
      end
    end

    after(:each) do
      WebflowSync.configure do |config|
        config.sync_webflow_slug = @old_sync_webflow_slug
        config.webflow_site_id = @old_webflow_site_id
      end
    end

    it 'updates item on Webflow', vcr: { cassette_name: 'webflow/update_item' } do
      title = 'Updated article title'
      article.update!(title:)

      result = WebflowSync::UpdateItemJob.perform_now(model_name, article.id)

      expect(result.dig('fieldData', 'name')).to eq title
    end

    it 'updates and publishes item on Webflow', vcr: { cassette_name: 'webflow/update_and_publish_item' } do # rubocop:disable RSpec/ExampleLength
      title = 'New live title'
      article.update!(title:)

      result = WebflowSync::UpdateItemJob.perform_now(model_name, article.id)

      item = WebflowSync::Api.new(webflow_site_id).get_item(model_name, article.webflow_item_id)
      expect(result.dig('fieldData', 'name')).to eq title
      expect(Time.zone.parse(item['lastPublished'])).to be >= Time.zone.parse(item['lastUpdated'])
    end

    context 'when record does not exist' do
      let(:record_id) { 1_234_567 }

      it 'does not sync' do
        allow(WebflowSync::Api).to receive(:new).and_return(mock_webflow_api)

        WebflowSync::UpdateItemJob.perform_now(model_name, record_id)

        expect(mock_webflow_api).not_to have_received(:update_item)
      end
    end

    context 'when webflow_site_id is nil' do
      let(:webflow_site_id) { nil }

      it 'does not sync' do
        allow(WebflowSync::Api).to receive(:new).and_return(mock_webflow_api)

        WebflowSync::UpdateItemJob.perform_now(model_name, article.id)

        expect(mock_webflow_api).not_to have_received(:update_item)
      end
    end

    context 'when webflow_item_id is nil' do
      let(:mock_webflow_api) do
        instance_double(WebflowSync::Api, update_item: nil, create_item: nil)
      end

      before(:each) do
        article.update!(webflow_item_id: nil)
      end

      it 'calls CreateItemJob' do
        allow(WebflowSync::Api).to receive(:new).and_return(mock_webflow_api)

        WebflowSync::UpdateItemJob.perform_now(model_name, article.id)

        expect(mock_webflow_api).to have_received(:create_item)
      end
    end

    context 'when slug name is passed' do
      let(:collection_slug) { 'stories' }
      let(:article) { create(:article, webflow_item_id: '65381893e6d401cdd3f3a363') }

      it 'updates item on Webflow', vcr: { cassette_name: 'webflow/update_sync_to_specified_collection' } do
        article.update!(title: 'Updated article title')

        result = WebflowSync::UpdateItemJob.perform_now(model_name, article.id, 'stories')

        expect(result.dig('fieldData', 'name')).to eq 'Updated article title'
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
