require "rails_helper"

# Tested through Organization, the first model that uses it.
RSpec.describe HasPublicId do
  let!(:organization) { create(:organization) }

  it "exposes a prefixed public id" do
    expect(organization.public_id).to start_with("org_")
    expect(PublicId.decode(organization.public_id, prefix: "org")).to eq(organization.id)
  end

  it "has no public id before the record is saved" do
    expect(build(:organization).public_id).to be_nil
  end

  describe ".find_by_public_id!" do
    it "finds the record" do
      expect(Organization.find_by_public_id!(organization.public_id)).to eq(organization)
    end

    it "raises RecordNotFound with the client's id for a missing record" do
      missing = PublicId.encode("org", SecureRandom.uuid_v7)

      expect { Organization.find_by_public_id!(missing) }
        .to raise_error(ActiveRecord::RecordNotFound, "No such organization: '#{missing}'")
    end

    it "raises RecordNotFound for a malformed id or the wrong prefix" do
      wrong_prefix = PublicId.encode("doc", organization.id)

      [ "garbage", organization.id, wrong_prefix ].each do |bad|
        expect { Organization.find_by_public_id!(bad) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "respects the scope of the relation it's called on" do
      expect { Organization.where(demo: true).find_by_public_id!(organization.public_id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
