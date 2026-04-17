#!/usr/bin/env ruby
require 'yaml'
require 'rainbow'

require_relative 'src/resolve.rb'

CONFIG = YAML.load_file('config.yml')

csv = Resolve::Hledger.get_unknown_transactions(CONFIG["starting_year"])
transactions = Resolve.generate_transactions_from_csv(csv)
category_list = Resolve::Hledger.generate_category_list(CONFIG["rules_directories"],CONFIG["accounts_list_file_path"])
colored_category_list = Resolve::Colorize.generate_category_list(category_list)

total_transactions = transactions.size
processed_count = 0

if transactions.empty?
    puts Rainbow("✓ Nenhuma transação desconhecida encontrada.").green
    exit 0
end

puts Rainbow("Iniciando categorização de #{total_transactions} transação(ões) desconhecida(s)...").cyan

loop do
    txns_list = Resolve.generate_transactions_list_for_loop(transactions)
    break if transactions.empty?

    remaining = transactions.size
    current_num = total_transactions - remaining + 1
    header = "Escolha transação (#{current_num}/#{total_transactions})"
    
    txn_raw = `echo '#{txns_list.join}' | sk --ansi --header="#{header}" -d '|' --tac --case=ignore`
    
    if txn_raw.empty? || txn_raw.strip.empty?
        puts Rainbow("\nCategorização interrompida pelo usuário.").yellow
        break
    end
    
    txn = txn_raw.strip.split("|")
    txn_full = transactions.select{|t| t[:date] == txn[0] and t[:description] == txn[1]}.first
    
    if txn_full.nil?
        puts Rainbow("✗ Erro: Transação não encontrada.").red
        next
    end

    category_header = "Escolha categoria (#{current_num}/#{total_transactions})"
    category_raw = `echo '#{colored_category_list.join("\n")}' | sk --ansi --header="#{category_header}" --tac --case=ignore`.strip
    
    if category_raw.nil? || category_raw.empty?
        puts Rainbow("\nCategorização interrompida pelo usuário.").yellow
        break
    end
    
    category_colored = category_raw.split("\n").first
    
    if category_colored.nil? || category_colored.strip.empty?
        puts Rainbow("✗ Erro: Categoria inválida.").red
        next
    end
    
    category_colored = category_colored.strip
    # Remover códigos ANSI e encontrar categoria original correspondente
    category_stripped = category_colored.gsub(/\033\[[0-9;]*m/, '')
    # Encontrar o índice na lista colorida que corresponde (comparando sem ANSI)
    category_index = colored_category_list.index { |c| c.gsub(/\033\[[0-9;]*m/, '') == category_stripped }
    category = category_index ? category_list[category_index] : category_stripped

    question = "Aplicar categoria #{category} a TODAS as transações com '#{txn_full[:description]}'?\n(SIM = regra geral para esta descrição | NÃO = regra específica apenas para este código)"
    match_all_txn = `echo 'NÃO\nSIM' | sk --header="#{question}" --ansi --print-cmd -i`.strip 
    
    if match_all_txn.empty?
        puts Rainbow("\nCategorização interrompida pelo usuário.").yellow
        break
    end

    if match_all_txn == "NÃO"
        comment = `sk --header="Digite comentário (prepend : para inibir seleção) ou ENTER para pular" --ansi --print-cmd -i`.strip 
        comment = comment.split("\n").first if comment && !comment.empty?
        comment = nil if comment.nil? || comment == ":" || comment.empty?
        
        rule = Resolve.match_to_specific_if_block(txn_full, category, comment)
        rules_file_path = Resolve.account_to_spec_rules_file(txn_full[:account])
        transactions_to_remove = transactions.select{|t| t[:code] == txn_full[:code]}
        transactions.delete_if{|t| t[:code] == txn_full[:code]}
        removed_count = transactions_to_remove.size
    else
        rule = Resolve.match_to_if_block(Resolve.cleanup_description(txn_full[:description]), category)
        rules_file_path = Resolve.category_to_rules_file(category)
        transactions_to_remove = transactions.select{|t| t[:description] == txn_full[:description]}
        transactions.delete_if{|t| t[:description] == txn_full[:description]}
        removed_count = transactions_to_remove.size
    end
    
    begin
        File.open(rules_file_path, "a+") do |f|
            f.write("\n" + rule)
        end
        processed_count += removed_count
        puts Rainbow("✓ Regra salva com sucesso em #{rules_file_path}").green
        puts Rainbow("  #{removed_count} transação(ões) removida(s) da lista (#{transactions.size} restante(s))").gray
    rescue => e
        puts Rainbow("✗ Erro ao salvar regra: #{e.message}").red
        puts Rainbow("  Arquivo: #{rules_file_path}").red
        exit 1
    end
end

if transactions.empty?
    puts "\n" + Rainbow("✓ Categorização concluída com sucesso!").green
    puts Rainbow("  #{processed_count} transação(ões) processada(s)").cyan
else
    puts "\n" + Rainbow("Categorização parcialmente concluída.").yellow
    puts Rainbow("  #{processed_count} transação(ões) processada(s)").cyan
    puts Rainbow("  #{transactions.size} transação(ões) restante(s)").yellow
end


