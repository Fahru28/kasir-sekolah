# Loads Leonardo instance metadata from .leonardo/instance.json into ENV:
#   mothership_url       -> MOTHERSHIP_URL   (default: https://llamapress.ai)
#   instance_name        -> MOTHERSHIP_INSTANCE_NAME
#   mothership_api_token -> MOTHERSHIP_API_TOKEN
#
# The Leonardo overlay's docker-compose mounts .leonardo/instance.json into the
# container as a single read-only file. Values already present in ENV (e.g. from
# .env via docker compose env_file) take precedence — this only fills in blanks.
# Missing or malformed instance.json never fails boot.
begin
  path = Rails.root.join(".leonardo", "instance.json")
  meta = File.exist?(path) ? JSON.parse(File.read(path)) : {}
rescue JSON::ParserError, Errno::EACCES => e
  Rails.logger.warn("leonardo_instance: could not read instance.json (#{e.class}: #{e.message})")
  meta = {}
end

ENV["MOTHERSHIP_URL"] ||= meta["mothership_url"].presence || "https://llamapress.ai"
ENV["MOTHERSHIP_INSTANCE_NAME"] ||= meta["instance_name"].presence

# Backfill the API token too. .env normally carries it (the mothership's
# EnvFileBuilder writes it, and it is NOT in the compose blanked-secrets list),
# but the mothership also syncs it into instance.json
# (UserInstance#sync_api_token_to_leonardo_instance_json), so this covers boxes
# whose .env predates that. Without it, error telemetry silently no-ops.
#
# Note the ordering above: MOTHERSHIP_URL always ends up set because of its
# default, so the token is the value that actually decides whether this box can
# talk to the mothership at all.
ENV["MOTHERSHIP_API_TOKEN"] ||= meta["mothership_api_token"].presence
