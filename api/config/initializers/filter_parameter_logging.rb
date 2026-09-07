Rails.application.config.filter_parameters += %i[
  password passw secret token _key crypt salt certificate otp ssn
  xai_api_key openai_api_key anthropic_api_key curator_runtime
]
