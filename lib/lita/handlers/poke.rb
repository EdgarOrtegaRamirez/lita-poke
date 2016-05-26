module Lita
  module Handlers
    class Poke < Handler
      route(/poke (\S*)$/i, :pokemon, command: true, help: {
        "poke <name>" => "find a pokemon by name",
        "poke <id>" => "find a pokemon by ID"
      })

      def pokemon(response)
        name = response.match_data[1]
        pokemon = PokeAPI::Pokemon.find name
        response.reply(render_template(:pokemon, pokemon: pokemon))
      rescue PokeAPI::Requester::NotFoundError
        response.reply("not found")
      end

      Lita.register_handler(self)
    end
  end
end
