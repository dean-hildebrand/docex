require "rails_helper"

RSpec.describe Organization do
  it "is valid from the factory" do
    expect(build(:organization)).to be_valid
  end

  it "requires a name" do
    organization = build(:organization, name: "")

    expect(organization).not_to be_valid
    expect(organization.errors[:name]).to include("can't be blank")
  end

  it "defaults to a non-demo organization with no page cap" do
    organization = create(:organization)

    expect(organization.demo).to be(false)
    expect(organization.daily_page_cap).to be_nil
  end

  describe "slug" do
    it "is derived from the name when blank" do
      expect(create(:organization, name: "Bakkerij De Vries B.V.").slug).to eq("bakkerij-de-vries-b-v")
    end

    it "is kept when given" do
      expect(create(:organization, name: "Acme", slug: "acme-eu").slug).to eq("acme-eu")
    end

    it "rejects uppercase, spaces and doubled hyphens" do
      %w[Acme acme--eu -acme acme_eu].push("acme eu").each do |slug|
        expect(build(:organization, slug: slug)).not_to be_valid, "expected #{slug.inspect} to be invalid"
      end
    end

    it "is unique" do
      create(:organization, slug: "acme")

      duplicate = build(:organization, slug: "acme")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it "is unique at the database level too" do
      create(:organization, slug: "acme")

      duplicate = build(:organization, slug: "acme")
      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "daily_page_cap" do
    it "accepts nil or a positive integer" do
      expect(build(:organization, daily_page_cap: nil)).to be_valid
      expect(build(:organization, daily_page_cap: 50)).to be_valid
    end

    it "rejects zero and negatives" do
      expect(build(:organization, daily_page_cap: 0)).not_to be_valid
      expect(build(:organization, daily_page_cap: -1)).not_to be_valid
    end

    it "is enforced by a check constraint" do
      # Explicit slug: save(validate: false) also skips the before_validation that derives it.
      organization = build(:organization, slug: "acme", daily_page_cap: 0)

      expect { organization.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /daily_page_cap_positive/)
    end
  end
end
