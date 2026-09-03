# Engine-contributed pins. Deliberately under the "controllers/" namespace so
# host apps' standard `eagerLoadControllersFrom("controllers", application)`
# auto-registers them — no host importmap.rb or controllers/index.js edits.
# These two keys are reserved; see docs/scaffold_templates.md.
pin "controllers/record_drawer_controller", to: "llama_bot_rails/controllers/record_drawer_controller.js"
pin "controllers/filter_panel_controller", to: "llama_bot_rails/controllers/filter_panel_controller.js"
