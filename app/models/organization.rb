class Organization < ApplicationRecord
  include HasPublicId
  public_id_prefix "org"

  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  before_validation :derive_slug, if: -> { slug.blank? && name.present? }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: SLUG_FORMAT, message: "must be lowercase letters, digits and single hyphens" }
  validates :daily_page_cap, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  private
    def derive_slug
      self.slug = name.parameterize
    end
end
