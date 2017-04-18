class TopicStatusUpdateSerializer < ApplicationSerializer
  attributes :id,
             :execute_at,
             :duration,
             :based_on_last_post,
             :status_type,
             :category_id

  def status_type
    TopicStatusUpdate.types[object.status_type]
  end
end
