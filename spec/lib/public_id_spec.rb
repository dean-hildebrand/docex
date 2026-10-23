require "rails_helper"

RSpec.describe PublicId do
  let(:uuid) { "0192b3c4-5d6e-7f80-9a1b-2c3d4e5f6a7b" }

  describe ".encode" do
    it "prefixes a 26-character base32 body" do
      expect(described_class.encode("doc", uuid)).to match(/\Adoc_[0-7][0-9A-HJKMNP-TV-Z]{25}\z/)
    end

    it "encodes the smallest and largest UUIDs" do
      expect(described_class.encode("doc", "00000000-0000-0000-0000-000000000000"))
        .to eq("doc_00000000000000000000000000")
      expect(described_class.encode("doc", "ffffffff-ffff-ffff-ffff-ffffffffffff"))
        .to eq("doc_7ZZZZZZZZZZZZZZZZZZZZZZZZZ")
    end

    it "keeps UUID sort order" do
      uuids = Array.new(50) { SecureRandom.uuid }.sort
      encoded = uuids.map { |u| described_class.encode("doc", u) }

      expect(encoded).to eq(encoded.sort)
    end

    it "rejects a bad prefix or UUID" do
      expect { described_class.encode("document", uuid) }.to raise_error(PublicId::InvalidError)
      expect { described_class.encode("doc", "not-a-uuid") }.to raise_error(PublicId::InvalidError)
    end
  end

  describe ".decode" do
    it "round-trips" do
      100.times do
        u = SecureRandom.uuid_v7
        expect(described_class.decode(described_class.encode("ext", u), prefix: "ext")).to eq(u)
      end
    end

    it "accepts a lowercase body" do
      encoded = described_class.encode("doc", uuid)
      lowercased = "doc_#{encoded.delete_prefix("doc_").downcase}"

      expect(described_class.decode(lowercased, prefix: "doc")).to eq(uuid)
    end

    it "rejects the wrong prefix" do
      encoded = described_class.encode("ext", uuid)

      expect { described_class.decode(encoded, prefix: "doc") }.to raise_error(PublicId::InvalidError, /expected a doc_ id/)
    end

    it "rejects malformed ids" do
      valid_body = described_class.encode("doc", uuid).delete_prefix("doc_")

      [
        nil,
        "",
        "doc",
        "doc_",
        uuid,
        "doc_#{valid_body}X",              # too long
        "doc_#{valid_body.chop}",          # too short
        "doc_8#{valid_body[1..]}",         # first character over 7: more than 128 bits
        "doc_#{valid_body.chop}U",         # U isn't in the alphabet
        "doc_#{valid_body.chop}I"          # neither is I
      ].each do |bad|
        expect { described_class.decode(bad, prefix: "doc") }
          .to raise_error(PublicId::InvalidError), "expected #{bad.inspect} to be rejected"
      end
    end
  end
end
