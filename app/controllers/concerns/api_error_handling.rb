# Turns every exception raised in an API controller into the one error shape
# described in ApiError. Handlers declared later take precedence, so the
# catch-all for unexpected errors comes first.
module ApiErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :render_internal_error
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ApiError, with: :render_api_error
  end

  private
    def render_api_error(error)
      render json: { error: error.to_h }, status: error.status
    end

    def render_not_found(error)
      render_api_error ApiError.new(type: :not_found, code: :resource_not_found, message: error.message)
    end

    def render_parameter_missing(error)
      render_api_error ApiError.new(type: :invalid_request, code: :parameter_missing,
        message: "Missing required parameter: #{error.param}", param: error.param)
    end

    # The real exception is reported and logged; the client only sees the
    # request id, which support can match to the log line.
    def render_internal_error(error)
      Rails.error.report(error, handled: true)
      render_api_error ApiError.new(type: :internal, code: :internal_error,
        message: "Something went wrong on our side. Request id: #{request.request_id}")
    end
end
