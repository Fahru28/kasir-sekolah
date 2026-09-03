require 'rails_helper'
require 'rails/generators'
require 'tmpdir'

RSpec.describe 'LlamaPress scaffold templates' do
  TEMPLATES_ROOT = LlamaBotRails::Engine.root.join('lib/llama_bot_rails/scaffold_templates')

  it 'registers the engine templates path with the host app' do
    expect(Rails.application.config.generators.templates).to include(TEMPLATES_ROOT.to_s)
  end

  it 'keeps the erb and tailwindcss template sets identical' do
    erb_dir = TEMPLATES_ROOT.join('erb/scaffold')
    tw_dir = TEMPLATES_ROOT.join('tailwindcss/scaffold')
    erb_files = Dir.children(erb_dir).sort
    expect(Dir.children(tw_dir).sort).to eq(erb_files)
    erb_files.each do |file|
      expect(File.read(tw_dir.join(file))).to eq(File.read(erb_dir.join(file))),
        "#{file} differs between erb/scaffold and tailwindcss/scaffold"
    end
  end

  describe 'generated output' do
    around do |example|
      Dir.mktmpdir do |dir|
        @destination = dir
        example.run
      end
    end

    def generate!
      # The resource_route hook aborts generation when the destination has no
      # routes file, so seed a stub for it to inject into.
      FileUtils.mkdir_p(File.join(@destination, 'config'))
      File.write(File.join(@destination, 'config/routes.rb'),
                 "Rails.application.routes.draw do\nend\n")
      Rails.application.load_generators
      Rails::Generators.invoke(
        'scaffold',
        %w[
          CiProbeWidget name:string email:string company:string status:string notes:text
          --quiet
        ],
        destination_root: @destination
      )
    end

    def read(relative)
      File.read(File.join(@destination, relative))
    end

    before { generate! }

    it 'injects the resource route' do
      expect(read('config/routes.rb')).to include('resources :ci_probe_widgets')
    end

    it 'produces the drawer/table index instead of the stock all-fields list' do
      index = read('app/views/ci_probe_widgets/index.html.erb')
      expect(index).to include('data-controller="filter-panel"')
      expect(index).to include('data: { turbo_frame: "record_drawer" }')
      expect(index).to include('hidden md:table-cell')
      expect(index).to include('form_with url: ci_probe_widgets_path, method: :get')
      # notes:text must not become a table column
      expect(index).not_to match(/>Notes</)
    end

    it 'pages through the shared styled nav instead of hand-rolling one' do
      index = read('app/views/ci_probe_widgets/index.html.erb')
      expect(index).to include('<%= llama_pagination_nav(@pagy) %>')
      expect(index).not_to include('@pagy.prev')
      expect(index).not_to include('@pagy.next')
    end

    it 'collapses the filter panel at every width and contains the table scroll' do
      index = read('app/views/ci_probe_widgets/index.html.erb')
      # The panel is width-independent: "hidden" with no md:block escape hatch,
      # and the toggle is not restricted to small screens.
      expect(index).to include(%q{"hidden" unless filters_active})
      expect(index).not_to include('hidden md:block')
      expect(index).not_to include('md:hidden rounded-md')
      # Without "relative" the sr-only header label escapes the scroll
      # container and drags a horizontal scrollbar onto the whole page.
      expect(index).to include('relative overflow-x-auto')
    end

    it 'renders a hero naming the resource' do
      index = read('app/views/ci_probe_widgets/index.html.erb')
      expect(index).to include('Ci probe widgets')
      expect(index).to include('View your ci probe widgets')
    end

    it 'puts search outside the collapsible panel so it is always reachable' do
      index = read('app/views/ci_probe_widgets/index.html.erb')
      search_bar, panel = index.split('data-filter-panel-target="panel"')

      expect(search_bar).to include('form.search_field :q')
      expect(panel).not_to include('form.search_field :q')
      # :q must not force the panel open — it is not a panel param.
      expect(index).to include(%q{filters_active = params.values_at(:from, :to)})
      expect(index).not_to include('params.values_at(:q')
    end

    it 'wraps search and filters in one form so they submit together' do
      index = read('app/views/ci_probe_widgets/index.html.erb')
      expect(index.scan('form_with url:').size).to eq(1)
    end

    it 'produces a row partial with drawer navigation and no notes cell' do
      row = read('app/views/ci_probe_widgets/_ci_probe_widget.html.erb')
      expect(row).to include('data-drawer-row')
      expect(row).to include('data: { turbo_frame: "record_drawer" }')
      expect(row).not_to include('.notes')
    end

    it 'wraps show/new/edit in the record drawer frame helper' do
      %w[show new edit].each do |view|
        expect(read("app/views/ci_probe_widgets/#{view}.html.erb"))
          .to include('llama_record_frame'), "#{view} missing llama_record_frame"
      end
      # the excluded field still appears in the drawer detail and form
      expect(read('app/views/ci_probe_widgets/show.html.erb')).to include('.notes')
      expect(read('app/views/ci_probe_widgets/_form.html.erb')).to include(':notes')
    end

    it 'generates a controller built on ScaffoldFiltering with a base_scope seam' do
      controller = read('app/controllers/ci_probe_widgets_controller.rb')
      expect(controller).to include('include LlamaBotRails::ScaffoldFiltering')
      expect(controller).to include('search_columns: %i[ name email company status ]')
      expect(controller).to include('def base_scope')
      expect(controller).to include('params.require(:ci_probe_widget).permit(')
    end

    it 'emits syntactically valid Ruby and ERB' do
      expect { RubyVM::InstructionSequence.compile(read('app/controllers/ci_probe_widgets_controller.rb')) }
        .not_to raise_error

      Dir[File.join(@destination, 'app/views/ci_probe_widgets/*.html.erb')].sort.each do |view|
        source = ActionView::Template::Handlers::ERB::Erubi.new(File.read(view), trim: true).src
        expect { RubyVM::InstructionSequence.compile(source) }
          .not_to raise_error, "invalid ERB output in #{File.basename(view)}"
      end
    end
  end
end
