class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  before_create :assign_uuid_v7, if: :uuid_primary_key?

  private
    # Postgres would otherwise fill UUID ids with gen_random_uuid() (v4, fully
    # random). UUIDv7 starts with a millisecond timestamp, so new rows land at
    # the end of the primary key index instead of at random positions, and ids
    # sort roughly by creation time.
    def assign_uuid_v7
      self.id ||= SecureRandom.uuid_v7
    end

    def uuid_primary_key?
      self.class.type_for_attribute(self.class.primary_key).type == :uuid
    end
end
