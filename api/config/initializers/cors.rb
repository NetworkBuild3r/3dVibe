Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("WEB_ORIGIN", "http://localhost:5173"),
            "http://127.0.0.1:5173",
            "http://localhost:4173"

    resource "*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: %w[Authorization Upload-Offset Upload-Length]
  end
end
