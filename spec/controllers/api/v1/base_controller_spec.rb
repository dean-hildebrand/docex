require "rails_helper"

# An anonymous subclass of BaseController with one action per kind of failure,
# to check each one comes back in the standard error shape.
RSpec.describe Api::V1::BaseController, type: :controller do
  controller(described_class) do
    def index
      case params[:fail]
      when "api_error"
        raise ApiError.new(type: :invalid_request, code: :schema_not_found,
          message: "No such schema: 'sch_123'", param: :schema_id)
      when "not_found"
        Organization.find_by_public_id!("org_00000000000000000000000000")
      when "missing_param"
        params.require(:document_id)
      when "unexpected"
        raise "database password is hunter2"
      else
        render json: { ok: true }
      end
    end
  end

  let(:error) { response.parsed_body["error"] }

  it "renders an ApiError with its status, code and param" do
    get :index, params: { fail: "api_error" }

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq(
      "error" => {
        "type" => "invalid_request",
        "code" => "schema_not_found",
        "message" => "No such schema: 'sch_123'",
        "param" => "schema_id"
      }
    )
  end

  it "renders RecordNotFound as 404 not_found" do
    get :index, params: { fail: "not_found" }

    expect(response).to have_http_status(:not_found)
    expect(error).to include("type" => "not_found", "code" => "resource_not_found")
    expect(error["message"]).to eq("No such organization: 'org_00000000000000000000000000'")
  end

  it "renders a missing parameter as 400 invalid_request with the param" do
    get :index, params: { fail: "missing_param" }

    expect(response).to have_http_status(:bad_request)
    expect(error).to include("type" => "invalid_request", "code" => "parameter_missing", "param" => "document_id")
  end

  it "renders unexpected errors as 500 internal without leaking the message" do
    expect(Rails.error).to receive(:report).with(instance_of(RuntimeError), handled: true)

    get :index, params: { fail: "unexpected" }

    expect(response).to have_http_status(:internal_server_error)
    expect(error).to include("type" => "internal", "code" => "internal_error")
    expect(error["message"]).not_to include("hunter2")
    expect(error["message"]).to include(request.request_id.to_s)
  end

  it "leaves successful responses alone" do
    get :index

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
  end
end
