# Converts internal UUIDs to the ids clients see, and back.
#
#   PublicId.encode("doc", "0192b3c4-...") # => "doc_01J9M..."
#   PublicId.decode("doc_01J9M...", prefix: "doc") # => "0192b3c4-..."
#
# The body is the UUID's 128 bits in Crockford base32 (26 characters). It's
# case-insensitive, has no I/L/O/U to avoid misreading, and sorts in the same
# order as the UUID, so UUIDv7 public ids still sort by creation time.
module PublicId
  ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".freeze
  BODY_LENGTH = 26
  PREFIX_FORMAT = /\A[a-z]{3}\z/
  # 26 * 5 = 130 bits, so the first character carries only 3 bits (0-7).
  BODY_FORMAT = /\A[0-7][#{ALPHABET}]{25}\z/
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  class InvalidError < ArgumentError; end

  def self.encode(prefix, uuid)
    raise InvalidError, "invalid prefix: #{prefix.inspect}" unless PREFIX_FORMAT.match?(prefix.to_s)
    raise InvalidError, "invalid UUID: #{uuid.inspect}" unless UUID_FORMAT.match?(uuid.to_s)

    number = uuid.delete("-").to_i(16)
    body = number.digits(32).reverse.map { |digit| ALPHABET[digit] }.join
    "#{prefix}_#{body.rjust(BODY_LENGTH, "0")}"
  end

  def self.decode(public_id, prefix:)
    given_prefix, body = public_id.to_s.split("_", 2)
    raise InvalidError, "expected a #{prefix}_ id" unless given_prefix == prefix

    body = body.to_s.upcase
    raise InvalidError, "malformed id: #{public_id.inspect}" unless BODY_FORMAT.match?(body)

    number = body.each_char.reduce(0) { |acc, char| (acc * 32) + ALPHABET.index(char) }
    hex = number.to_s(16).rjust(32, "0")
    [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
  end
end
