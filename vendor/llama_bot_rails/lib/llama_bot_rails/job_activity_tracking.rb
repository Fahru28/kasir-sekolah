# frozen_string_literal: true

module LlamaBotRails
  # Gives background jobs the same activity context a request gets, so a row
  # that changed at 3am is attributable to ReconcileInvoicesJob instead of
  # appearing as an anonymous mutation.
  #
  # Included into ActiveJob::Base by the engine. Rails resets CurrentAttributes
  # around each perform, so this only has to set values, never clear them.
  #
  # NOTE (phase 3): the correlation_id is fresh per job. Carrying the enqueuing
  # request's correlation across the queue boundary needs the id serialized
  # into the job arguments — deliberately not done yet. `parent_event_id`
  # is the seam for it.
  module JobActivityTracking
    extend ActiveSupport::Concern

    included do
      around_perform do |job, block|
        LlamaBotRails::JobActivityTracking.apply_context(job)
        block.call
      end
    end

    def self.apply_context(job)
      current = LlamaBotRails::Current
      current.source ||= "background_job"
      current.actor_type ||= "System"
      current.actor_label ||= job.class.name
      current.job_class = job.class.name
      current.job_id = job.job_id

      return unless defined?(::PaperTrail) && ::PaperTrail.respond_to?(:request)

      ::PaperTrail.request.whodunnit = job.class.name
      ::PaperTrail.request.controller_info = current.paper_trail_info
    rescue StandardError => e
      Rails.logger.warn("[llama_bot_rails] activity context not set for #{job.class}: #{e.class}: #{e.message}")
    end
  end
end
