module LlamaBotRails
  module ScaffoldHelper
    # Wraps drawer-able record content (show/new/edit) in the shared
    # "record_drawer" Turbo Frame — but only for frame requests. Direct visits
    # render the same content as a normal full page, without duplicating the
    # frame id already present in the layout's drawer shell.
    def llama_record_frame(&block)
      if turbo_frame_request?
        turbo_frame_tag("record_drawer", &block)
      else
        capture(&block)
      end
    end
  end
end
