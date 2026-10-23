# Gives a model a prefixed public id and a finder for it.
#
#   class Document < ApplicationRecord
#     include HasPublicId
#     public_id_prefix "doc"
#   end
#
#   document.public_id                                   # => "doc_01J9M..."
#   Current.organization.documents.find_by_public_id!(params[:id])
#
# The finder is a class method, so it works on any relation and keeps that
# relation's scope. That's what makes tenant scoping work.
module HasPublicId
  extend ActiveSupport::Concern

  included do
    class_attribute :_public_id_prefix, instance_accessor: false
  end

  class_methods do
    def public_id_prefix(prefix = nil)
      return _public_id_prefix if prefix.nil?

      self._public_id_prefix = prefix
    end

    # Malformed ids, ids with the wrong prefix and ids that don't exist all
    # raise the same RecordNotFound, so the API answers each with a plain 404.
    def find_by_public_id!(public_id)
      uuid = PublicId.decode(public_id, prefix: public_id_prefix)
      find_by(id: uuid) || raise_public_id_not_found(public_id)
    rescue PublicId::InvalidError
      raise_public_id_not_found(public_id)
    end

    private
      def raise_public_id_not_found(public_id)
        raise ActiveRecord::RecordNotFound.new("No such #{model_name.human.downcase}: '#{public_id}'",
          name, primary_key, public_id)
      end
  end

  def public_id
    PublicId.encode(self.class.public_id_prefix, id) if id
  end
end
