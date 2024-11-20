#!/usr/bin/env ruby
require 'yaml'
require 'rainbow'

require_relative 'src/resolve.rb'

CONFIG = YAML.load_file('config.yml')

# def account_txn_match(txn)
#     if txn[:code]
#         txn[:code]
#     end
# end

csv = Resolve::Hledger.get_unknown_transactions(CONFIG["starting_year"])
transactions = Resolve.generate_transactions_from_csv(csv)
category_list = Resolve::Hledger.generate_category_list(CONFIG["rules_directories"],CONFIG["accounts_list_file_path"])
colored_category_list = Resolve::Colorize.generate_category_list(category_list)

loop do
    txns_list = Resolve.generate_transactions_list_for_loop(transactions)
    break if transactions.empty?

    txn_raw = `echo '#{txns_list.join}' | sk --ansi --header="Choose transaction" -d '|' --tac --case=ignore`
    break if txn_raw.empty?
    txn = txn_raw.split("|")
    txn_full = transactions.select{|t| t[:date] == txn[0] and t[:description] == txn[1]}.first

    category = `echo '#{colored_category_list.join("\n")}' | sk --ansi --header="Choose category"  --tac --case=ignore`.strip.split("\n")[0]
    break if category.nil?

    question = "Do you want all transactions with #{txn_full[:description]} to be classified as #{category}?"
    match_all_txn = `echo 'NO\nYES' | sk --header="#{question}" --ansi --print-cmd -i`.strip 
    break if match_all_txn.empty?

    if match_all_txn == "NO"
        comment = `echo '#{txn_raw}#{category}' | sk --header="Enter comment (prepend : to inhibit selection)" --ansi --print-cmd -i` 
        comment = comment.split("\n")[0]
        comment = nil if (comment == ":" or comment.empty?)
        #rule = match_to_specific_if_block(account_txn_match(txn_full),category, comment)
        rule = Resolve.match_to_specific_if_block(txn_full,category, comment)
        rules_file_path = Resolve.account_to_spec_rules_file(txn_full[:account])
        transactions.delete_if{|t| t[:code] == txn_full[:code]}
    else
        rule = Resolve.match_to_if_block(Resolve.cleanup_description(txn_full[:description]),category)
        rules_file_path = Resolve.category_to_rules_file(category)
        transactions.delete_if{|t| t[:description] == txn_full[:description]}
    end
    File.open(rules_file_path, "a+") {|f| f.write("\n"+rule)}
end


