# An error a client should see, rendered by ApiErrorHandling as:
#
#   {"error": {"type": "invalid_request", "code": "schema_not_found",
#              "message": "No such schema: 'sch_01J...'", "param": "schema_id"}}
#
# `type` is the broad category clients branch on (and sets the HTTP status);
# `code` is the specific reason; `param` names the request field at fault.
class ApiError < StandardError
  STATUSES = {
    "authentication" => 401,
    "permission" => 403,
    "invalid_request" => 400,
    "not_found" => 404,
    "conflict" => 409,
    "rate_limited" => 429,
    "internal" => 500
  }.freeze

  attr_reader :type, :code, :param

  def initialize(type:, code:, message:, param: nil)
    raise ArgumentError, "unknown error type: #{type}" unless STATUSES.key?(type.to_s)

    @type = type.to_s
    @code = code.to_s
    @param = param&.to_s
    super(message)
  end

  def status
    STATUSES.fetch(type)
  end

  def to_h
    { type:, code:, message:, param: }.compact
  end
end
