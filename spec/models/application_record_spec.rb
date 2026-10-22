require "rails_helper"

# Tested through Organization because ApplicationRecord is abstract.
RSpec.describe ApplicationRecord do
  it "assigns a version 7 UUID as the primary key" do
    organization = create(:organization)

    # Version is the first hex digit of the third group: xxxxxxxx-xxxx-7xxx-...
    expect(organization.id).to match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/)
  end

  it "embeds the creation time in the first 48 bits of the id" do
    organization = create(:organization)

    milliseconds = organization.id.delete("-")[0, 12].to_i(16)
    expect(Time.at(milliseconds / 1000.0)).to be_within(1.second).of(organization.created_at)
  end

  it "keeps an id that was set explicitly" do
    id = SecureRandom.uuid

    expect(create(:organization, id: id).id).to eq(id)
  end
end
