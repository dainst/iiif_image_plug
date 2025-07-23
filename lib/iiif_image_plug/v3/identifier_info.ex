defmodule IIIFImagePlug.V3.IdentifierInfo do
  @enforce_keys :path
  defstruct path: nil, rights: nil, part_of: [], see_also: [], service: []

  @type t :: %__MODULE__{
          path: String.t(),
          rights: String.t() | nil,
          part_of: list(),
          see_also: list(),
          service: list()
        }
end
