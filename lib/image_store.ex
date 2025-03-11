defmodule ImageStore do
  def identifier_to_path(identifier) do
    "image_store/#{identifier}"
  end
end
