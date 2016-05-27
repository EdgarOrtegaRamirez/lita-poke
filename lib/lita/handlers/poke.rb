module Lita
  module Handlers
    class Poke < Handler
      route(/(poke|pokemon) (\S*)$/i, :pokemon_info, command: true, help: {
        "(poke|pokemon) <name>" => "information about a pokemon by ID or name",
      })
      route(/(poke|pokemon) (pic|photo) (\S*)$/i, :pokemon_pic, command: true, help: {
        "(poke|pokemon) (pic|photo) <name>" => "Picture of a pokemon by ID or name",
      })
      route(/poke type (\w+-?\w*)(\/|,? ?)?(\w+)?$/i, :type_info, command: true, help: {
        "poke type <name>" => "information about a pokémon type by name",
        "poke type <pokemon name>" => "information about the types of a pokémon by name",
        "poke type <name1>(/|,| )<name2>" => "information about a dual pokémon type by name",
      })

      def pokemon_pic(response)
        name = response.match_data[3]
        pokemon = PokeAPI::Pokemon.find name
        target = if response.message.private_message?
                   response.message.user
                 else
                   response.message.room_object
                 end
        attachment = Lita::Adapters::Slack::Attachment.new(pokemon.name, {
          color: pokemon.species.color_hex,
          fallback: pokemon.name,
          image_url: pokemon.animated_thumbnail
        })
        robot.chat_service.send_attachments(target, attachment)
      rescue PokeAPI::Requester::NotFoundError
        response.reply("not found")
      rescue => e
        response.reply("an error occurred: `#{e.message}`")
      end

      def type_info(response)
        dual_type = false
        template = nil
        types = []
        name1 = response.match_data[1]
        name2 = response.match_data[3]
        target = if response.message.private_message?
                   response.message.user
                 else
                   response.message.room_object
                 end
        if PokeAPI::Type.valid?(name1)
          template = :type
          types << PokeAPI::Type.find(name1)
          if PokeAPI::Type.valid?(name2)
            dual_type = true
            types << PokeAPI::Type.find(name2)
          end
        else
          template = :pokemon
          pokemon = PokeAPI::Pokemon.find name1
          dual_type = true if pokemon.types.count == 2
          types = pokemon.types.map(&:reload)
        end
        if dual_type
          damage_from = types.each_with_object(Hash.new(1.0)) do |type, hsh|
            {0.0 => :no_damage_from, 0.5 => :half_damage_from, 2.0 => :double_damage_from}.each do |score, method|
              type.damage_relations.send(method).each do |damaging_type|
                hsh[damaging_type.name] = hsh[damaging_type.name] * score
              end
            end
          end.delete_if { |type, score| score == 1.0 }
          damage_from = damage_from.group_by { |k, v| v }
          titles = { 0.0 => "No damage from", 0.25 => "Quarter damage from", 0.5 => "Half damage from", 2.0 => "Double damage from", 4.0 => "Four times damage from" }
          fields = damage_from.each_with_object([]) do |(damage, grouped_types), ary|
            ary << { title: titles[damage], value: grouped_types.map { |type| type[0] }.map(&:capitalize).join(", "), short: true }
          end
          if template == :type
            attachment = Lita::Adapters::Slack::Attachment.new(nil, {
              color: types[0].color_hex,
              fallback: types.map(&:name).map(&:capitalize).join("/"),
              title: types.map(&:name).map(&:capitalize).join("/"),
              fields: fields
            })
          else
            attachment = Lita::Adapters::Slack::Attachment.new(types.map(&:name).map(&:capitalize).join("/"), {
              color: types[0].color_hex,
              fallback: pokemon.name.capitalize,
              title: pokemon.name.capitalize,
              title_link: "http://bulbapedia.bulbagarden.net/wiki/#{pokemon.name}",
              fields: fields,
              image_url: pokemon.animated_thumbnail
            })
          end
        else
          type = types[0]
          fields = if template == :type
                     [
                       { title: "Double damage from", attribute: :double_damage_from },
                       { title: "Double damage to", attribute: :double_damage_to },
                       { title: "Half damage from", attribute: :half_damage_from },
                       { title: "Half damage to", attribute: :half_damage_to },
                       { title: "No damage from", attribute: :no_damage_from },
                       { title: "No damage to", attribute: :no_damage_to },
                     ]
                   else
                     [
                       { title: "Double damage from", attribute: :double_damage_from },
                       { title: "Half damage from", attribute: :half_damage_from },
                       { title: "No damage from", attribute: :no_damage_from },
                     ]
                   end
          fields = fields.each_with_object([]) do |field, ary|
            if type.damage_relations.send(field[:attribute]).any?
              ary << {
                title: field[:title],
                value: type.damage_relations.send(field[:attribute]).map(&:name).map(&:capitalize).join(", "),
                short: true
              }
            end
          end
          if template == :type
            attachment = Lita::Adapters::Slack::Attachment.new(nil, {
              color: type.color_hex,
              fallback: type.name.capitalize,
              title: type.name.capitalize,
              title_link: "http://bulbapedia.bulbagarden.net/wiki/#{type.name}_(type)",
              fields: fields
            })
          else
            attachment = Lita::Adapters::Slack::Attachment.new(types.map(&:name).map(&:capitalize).join("/"), {
              color: type.color_hex,
              title: pokemon.name.capitalize,
              title_link: "http://bulbapedia.bulbagarden.net/wiki/#{pokemon.name}",
              fields: fields,
              image_url: pokemon.animated_thumbnail
            })
          end
        end
        robot.chat_service.send_attachments(target, attachment)
      rescue PokeAPI::Requester::NotFoundError
        response.reply("not found")
      rescue => e
        response.reply("an error occurred: `#{e.message}`")
      end

      def pokemon_info(response)
        name = response.match_data[2]
        pokemon = PokeAPI::Pokemon.find name
        target = if response.message.private_message?
                   response.message.user
                 else
                   response.message.room_object
                 end
        types = pokemon.types.map(&:name).join("/")
        abilities = pokemon.abilities.map { |ability| "#{ability.name}#{' (hidden)' if ability.hidden?}" }.join("\n")
        ev_yields = pokemon.stats.select { |stat| stat.effort != 0 }.map { |stat| "#{stat.name} #{stat.effort}" }.join("\n")
        evolution_chain = get_evolution_chain(pokemon.species.evolution_chain.chain)
        pokedex_entry = pokemon.species.flavor_text_entries.find { |entry| entry.language == 'en' } || pokemon.species.flavor_text_entries.first
        attachment = Lita::Adapters::Slack::Attachment.new(pokedex_entry.text, {
          color: pokemon.species.color_hex,
          fallback: pokemon.name,
          title: "#{pokemon.id}. #{pokemon.name}",
          title_link: "http://bulbapedia.bulbagarden.net/wiki/#{pokemon.name}",
          fields: [
            { title: "Types", value: types, short: true },
            { title: "Abilities", value: abilities, short: true },
            { title: "EV Yield", value: ev_yields, short: false },
            { title: "Evolution Chain", value: evolution_chain, short: false },
          ],
          image_url: pokemon.animated_thumbnail
        })
        robot.chat_service.send_attachments(target, attachment)
      rescue PokeAPI::Requester::NotFoundError
        response.reply("not found")
      rescue => e
        response.reply("an error occurred: `#{e.message}`")
      end

      def get_evolution_chain(chain)
        evolution_chain = chain.name
        if chain.evolves_to.any?
          evolution_chain << "\n\n"
          evolution_chain << chain.evolves_to.map do |ch|
            "#{ch.name} #{get_evolution_details(ch.evolution_details)}"
          end.join("\n")
          chain.evolves_to.each do |ch|
            if ch.evolves_to.any?
              evolution_chain << "\n\n"
              evolution_chain << ch.evolves_to.map do |ch2|
                "#{ch2.name} #{get_evolution_details(ch2.evolution_details)}"
              end.join("\n")
            end
          end
        end
        evolution_chain
      end

      def get_evolution_details(evolution_details)
        case evolution_details.trigger
        when "level-up"
          string = "(level "
          string << (evolution_details.min_level ? evolution_details.min_level.to_s : "up")
          string << " | #{evolution_details.min_happiness} happiness" if evolution_details.min_happiness
          string << " | #{evolution_details.min_affection} affection" if evolution_details.min_affection
          string << " | location #{evolution_details.location}" if evolution_details.location
          string << " | knowing #{evolution_details.known_move}" if evolution_details.known_move
          string << " | knowing a #{evolution_details.known_move_type} type move" if evolution_details.known_move_type
          string << " | #{evolution_details.time_of_day}" if evolution_details.time_of_day
          string << ")"
        when "trade"
          if evolution_details.held_item
            "(trading with #{evolution_details.held_item})"
          else
            "(trading)"
          end
        when "use-item"
          "(using #{evolution_details.item})"
        when "shed"
          "(shedding)"
        end
      end

      Lita.register_handler(self)
    end
  end
end
