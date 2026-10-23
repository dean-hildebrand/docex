# Parent of every /v1 controller. JSON only, no sessions or cookies
# (ActionController::API), with errors rendered in the standard shape.
module Api
  module V1
    class BaseController < ActionController::API
      include ApiErrorHandling
    end
  end
end
