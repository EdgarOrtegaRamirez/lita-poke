require "lita"
require "pokeapi"

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

require "lita/handlers/poke"

Lita::Handlers::Poke.template_root File.expand_path(
  File.join("..", "..", "templates"),
 __FILE__
)
