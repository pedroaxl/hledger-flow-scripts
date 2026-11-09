#!/usr/bin/env ruby
require 'yaml'
require 'rainbow'
require 'tmpdir'

require_relative 'src/resolve.rb'

CONFIG = YAML.load_file('config.yml') rescue {}

csv = Resolve::Hledger.get_unknown_transactions(CONFIG["starting_year"])
transactions = Resolve.generate_transactions_from_csv(csv)
category_list = Resolve::Hledger.generate_category_list(CONFIG["rules_directories"],CONFIG["accounts_list_file_path"])
colored_category_list = Resolve::Colorize.generate_category_list(category_list)
history = Resolve::Hledger.categorized_history(category_list)
ambiguous_keys = Resolve::Hledger.ambiguous_keys(history)
sk_color = Resolve::Theme.sk_color(CONFIG["sk_color"])

total_transactions = transactions.size
processed_count = 0
undo_stack = []
status = nil

if transactions.empty?
    puts Rainbow("✓ Nenhuma transação desconhecida encontrada.").green.bold
    exit 0
end

puts Rainbow("Iniciando categorização de #{total_transactions} transação(ões) desconhecida(s)...").bold

begin
    Dir.mktmpdir("resolve") do |preview_dir|
        until transactions.empty?
            groups = Resolve.group_transactions(transactions, ambiguous_keys)
            similar_by_group = groups.map {|g| Resolve::Similarity.similar(g[:description], history)}
            groups.each_with_index do |group, id|
                File.write(File.join(preview_dir, "#{id}.txt"), Resolve::Screen.preview(group, similar_by_group[id]))
            end

            header = [
                "Faltam #{Resolve::Screen.count_label(transactions.size)} · #{processed_count}/#{total_transactions} feitas",
                status,
                "Enter: categorizar · Ctrl-Z: desfazer a última · Esc: sair",
                (groups.any? {|g| g[:ambiguous]} ? "• categoria pode variar: uma linha por transação" : nil)
            ].compact.join("\n")
            rows = groups.each_with_index.map {|group, id| Resolve::Screen.group_row(group, id)}
            picked = Resolve::Skim.pick(rows, header: header, color: sk_color,
                                        binds: ["ctrl-z:accept(desfazer)"],
                                        preview: "cat #{Shellwords.escape(preview_dir)}/{1}.txt")

            if picked.nil?
                puts Rainbow("\nCategorização interrompida pelo usuário.").bold
                break
            end

            if picked.action == "desfazer"
                entry = undo_stack.pop
                if entry.nil?
                    status = "Nada para desfazer."
                else
                    begin
                        Resolve::RuleFile.undo(entry)
                        transactions.concat(entry[:transactions])
                        processed_count -= entry[:transactions].size
                        status = "↶ Desfeito: #{entry[:label]}"
                    rescue => e
                        status = "✗ Não foi possível desfazer: #{e.message}"
                    end
                end
                next
            end

            next if picked.id.nil?
            group = groups[picked.id]
            suggestions = Resolve::Similarity.suggestions(similar_by_group[picked.id])

            category_header = [Resolve::Screen.group_summary(group), Resolve::Screen.category_keys_hint(group)].join("\n")
            category_rows = Resolve::Screen.category_rows(category_list, colored_category_list, suggestions)
            choice = Resolve::Skim.pick(category_rows, header: category_header, color: sk_color,
                                        binds: [group[:ambiguous] ? "ctrl-g:accept(geral)" : "ctrl-s:accept(especifica)"],
                                        preview: Resolve::Screen.preview_command(preview_dir, picked.id))
            next if choice.nil? || choice.id.nil?
            category = category_list[choice.id]

            specific = group[:ambiguous] ? choice.action != "geral" : choice.action == "especifica"
            if specific
                txn = group[:transactions].first
                if group[:transactions].size > 1
                    txn_rows = group[:transactions].each_with_index.map {|t, id| Resolve::Screen.transaction_row(t, id)}
                    txn_choice = Resolve::Skim.pick(txn_rows, header: "Aplicar #{category} a qual transação? · Esc: voltar", color: sk_color)
                    next if txn_choice.nil? || txn_choice.id.nil?
                    txn = group[:transactions][txn_choice.id]
                end

                print "Comentário para #{txn[:description]} (Enter para pular): "
                comment = Resolve::Screen.clean_comment($stdin.gets)

                rule = Resolve.match_to_specific_if_block(txn, category, comment)
                rules_file_path = Resolve.account_to_spec_rules_file(txn[:account])
                removed = transactions.select {|t| t[:code] == txn[:code]}
                kind = "regra específica"
                label_description = txn[:description]
            else
                rule = Resolve.match_to_if_block(Resolve.cleanup_description(group[:description]), category)
                rules_file_path = Resolve.category_to_rules_file(category)
                unless File.exist?(rules_file_path)
                    status = "✗ #{category} não tem arquivo de regras gerais (#{rules_file_path}). Use uma regra só para esta transação."
                    next
                end
                removed = group[:siblings]
                kind = "regra geral"
                label_description = group[:description]
            end

            begin
                entry = Resolve::RuleFile.append(rules_file_path, rule)
            rescue => e
                status = "✗ Erro ao salvar em #{rules_file_path}: #{e.message}"
                next
            end

            transactions -= removed
            processed_count += removed.size
            label = "#{label_description} → #{category} · #{kind} · #{Resolve::Screen.count_label(removed.size)} · #{rules_file_path}"
            undo_stack.push(entry.merge(transactions: removed, label: label))
            status = "✓ #{label}"
            puts Rainbow(status).green.bold
        end
    end
rescue Interrupt
    puts Rainbow("\nCategorização interrompida pelo usuário.").bold
end

if transactions.empty?
    puts "\n" + Rainbow("✓ Categorização concluída com sucesso!").green.bold
    puts "  #{processed_count} transação(ões) processada(s)"
else
    puts "\n" + Rainbow("Categorização parcialmente concluída.").bold
    puts "  #{processed_count} transação(ões) processada(s)"
    puts "  #{transactions.size} transação(ões) restante(s)"
end
