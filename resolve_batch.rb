#!/usr/bin/env ruby
require 'yaml'
require 'rainbow'
require 'json'

require_relative 'src/resolve.rb'
# require_relative 'hledger-flow-scripts/src/resolve.rb'

CONFIG = YAML.load_file('config.yml')

csv = Resolve::Hledger.get_unknown_transactions(CONFIG["starting_year"])
transactions = Resolve.generate_transactions_from_csv(csv)
category_list = Resolve::Hledger.generate_category_list(CONFIG["rules_directories"],CONFIG["accounts_list_file_path"])
colored_category_list = Resolve::Colorize.generate_category_list(category_list)

loop do
    transactions_by_date = Resolve::Batch.group_transactions_by_date(transactions)
    txns_list = Resolve::Batch.generate_grouped_transactions_list_for_loop(transactions_by_date)
    break if transactions_by_date.empty?

    txn_raw = `echo '#{txns_list.join}' | sk --ansi --header="Choose date and type" -d '|' --tac --case=ignore`
    break if txn_raw.empty?
    transactions_selected = Resolve::Batch.filter_transactions_from_date_type transactions, txn_raw
    puts transactions_selected

    category = `echo '#{colored_category_list.join("\n")}' | sk --ansi --header="Choose category"  --tac --case=ignore`.strip.split("\n")[0]
    break if category.nil?

    summary = Resolve::Batch.summary_message txn_raw, category
    confirmation = `echo 'NO\nYES' | sk --header="#{summary.join}" --ansi --print-cmd -i`.strip 

    break if confirmation != "YES"

    comment = `echo '#{txn_raw}#{category}' | sk --header="Enter comment (prepend : to inhibit selection)" --ansi --print-cmd -i` 
    comment = comment.split("\n")[0]
    comment = nil if (comment == ":" or comment.empty?)

    transactions_selected.each do |txn_full|
        rule = Resolve.match_to_specific_if_block(txn_full,category, comment)
        rules_file_path = Resolve.account_to_spec_rules_file(txn_full[:account])
        transactions.delete_if{|t| t[:code] == txn_full[:code]}
        File.open(rules_file_path, "a+") {|f| f.write("\n"+rule)}
    end
    
end

