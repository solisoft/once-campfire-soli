class PwaController < ApplicationController
  # GET /webmanifest
  # GET /webmanifest.json
  def manifest
    {"status": 200, "headers": {"Content-Type": "application/json; charset=utf-8"},
     "body": PwaAssets.manifest(@_account, RoomPage.base_url(req))}
  end

  # GET /service-worker
  # GET /service-worker.js — at the root, so its scope is the whole app.
  def service_worker
    {"status": 200, "headers": {"Content-Type": "text/javascript; charset=utf-8"}, "body": PwaAssets.SERVICE_WORKER}
  end
end
