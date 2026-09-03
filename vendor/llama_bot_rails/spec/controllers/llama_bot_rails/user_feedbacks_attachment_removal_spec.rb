require 'rails_helper'
require_relative '../../support/feedback_tables'

# Pins "I can take an image back off my feedback while editing it".
#
# The edit form re-submits every existing attachment as a hidden signed_id so a plain
# text edit doesn't wipe the files. With no way to drop one of those hidden fields, the
# set could only ever grow -- the edit page had no remove control at all, so a wrong or
# sensitive screenshot could only be removed from the show page (Michaela, 2026-08-02).
RSpec.describe LlamaBotRails::UserFeedbacksController, type: :controller do
  routes { LlamaBotRails::Engine.routes }
  render_views

  before(:all) do
    LlamaBotRails::SpecSupport::FeedbackTables.build!
    LlamaBotRails::SpecSupport::FeedbackTables.wire_helpers!(described_class)
  end

  let(:user) { double('User', id: 123, email: 'user@example.com') }

  let!(:feedback) do
    LlamaBotRails::UserFeedback.create!(
      title: 'Wrong screenshot attached',
      description: 'I uploaded the wrong image',
      feedback_type: 'bug',
      user_id: user.id,
      user_email: user.email
    )
  end

  before do
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
  end

  def attach(filename, content_type: 'image/png')
    feedback.attachments.attach(
      io: StringIO.new('fake-bytes'),
      filename: filename,
      content_type: content_type
    )
    feedback.attachments.reload.detect { |a| a.filename.to_s == filename }
  end

  describe 'GET #edit' do
    let!(:screenshot) { attach('screenshot.png') }

    before { get :edit, params: { id: feedback.id } }

    it 'gives every already-saved attachment its own remove control' do
      expect(response.body).to include('data-existing-attachment')
      expect(response.body).to include('removeExistingAttachment(this)')
      expect(response.body).to include('function removeExistingAttachment(button)')
    end

    it 'still re-submits the attachment so an unrelated edit does not wipe it' do
      expect(response.body).to include(screenshot.signed_id)
    end

    it 'submits a blank entry so removing the LAST attachment is not a no-op' do
      # Without it the form sends no attachments key at all once every row is dropped,
      # and Rails leaves the existing files alone.
      expect(response.body).to match(
        /<input[^>]*name="user_feedback\[attachments\]\[\]"[^>]*type="hidden"[^>]*value=""/
      )
    end

    it 'shows the image itself, not just its filename' do
      expect(response.body).to match(/<img[^>]*#{Regexp.escape(screenshot.filename.to_s)}\?disposition=inline/)
    end
  end

  describe 'PATCH #update' do
    let!(:keeper) { attach('keep-me.png') }
    let!(:goner) { attach('remove-me.png') }

    it 'purges the attachment whose hidden field the user removed' do
      patch :update, params: {
        id: feedback.id,
        user_feedback: { title: feedback.title, attachments: [ '', keeper.signed_id ] }
      }

      filenames = feedback.reload.attachments.map { |a| a.filename.to_s }
      expect(filenames).to eq([ 'keep-me.png' ])
    end

    it 'purges every attachment when the user removes them all' do
      patch :update, params: {
        id: feedback.id,
        user_feedback: { title: feedback.title, attachments: [ '' ] }
      }

      expect(feedback.reload.attachments).to be_empty
    end
  end
end
