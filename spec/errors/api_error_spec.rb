require "rails_helper"

RSpec.describe ApiError do
  it "maps its type to an HTTP status" do
    expect(described_class.new(type: :conflict, code: :x, message: "m").status).to eq(409)
  end

  it "serializes without a param when none is given" do
    error = described_class.new(type: :not_found, code: :resource_not_found, message: "No such document")

    expect(error.to_h).to eq(type: "not_found", code: "resource_not_found", message: "No such document")
  end

  it "rejects unknown types" do
    expect { described_class.new(type: :teapot, code: :x, message: "m") }.to raise_error(ArgumentError)
  end
end
