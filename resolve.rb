#!/usr/bin/env ruby
require 'csv'
require 'yaml'
require 'rainbow'
require 'i18n'

CONFIG = YAML.load_file('config.yml')
COLORS = [:red, :green, :yellow, :blue, :magenta, :cyan, :white] # removed :black
I18n.available_locales = [:en]

def cleanup_description(desc)
    if /(\d{1,2})\/\d{1,2}$/.match? desc
        match = /(.*)(\d{1,2}\/\d{1,2})$/.match(desc)
        desc = match[1].strip
    end
    desc.gsub("*",'\*').gsub("+","\+")
end

def account_txn_match(txn)
    if txn[:code]
        txn[:code]
    end
end

def journals_from_multiple_people?  
    Dir["./import/*"].map{|p| File.directory?(p)}.count(true) > 1
end

def account_to_spec_rules_file account
    account_parsed = account.split(':')
    if journals_from_multiple_people? 
        person_name = I18n.transliterate(account_parsed[1]).downcase
        bank_name = I18n.transliterate(account_parsed[2]).downcase
        account_name = I18n.transliterate(account_parsed[3].gsub(" ","")).downcase
    else
        person_name = I18n.transliterate(Dir["./import/*"].filter{|p| File.directory?(p)}.first.split("/").last)
        bank_name = I18n.transliterate(account_parsed[2]).downcase
        account_name = I18n.transliterate(account_parsed[1].gsub(" ","")).downcase
        account_name.chop if account_name[-1] == "s" # remove plural
    end
    "./import/#{person_name}/#{bank_name}/#{account_name}/#{bank_name}-#{account_name}-specific.rules"
end

def category_to_rules_file category
    c = category.split(":")
    if journals_from_multiple_people?
        "./rules/#{c[0].downcase}/#{I18n.transliterate(c[2]).downcase}.psv"
    else
        "./rules/#{c[0].downcase}/#{I18n.transliterate(c[1]).downcase}.psv"
    end
end

def match_to_if_block(match_str, account)
    "#{match_str}|#{account}"
end

def match_to_specific_if_block(match_str, account, comment)
    "#{match_str}|#{account}|#{comment}"
end

def parse_csv_line(l)
    {"index": l[0], "date": l[1], "code":l[2], "description":l[3], "account": l[4], "amount":l[5] }
end

def colorize_description(description, i)
    Rainbow(description).bg(i % 2 == 0 ? :blue : :cyan)
end

def colorize_account(account,high_level_category_colors,category_key_range)
    Rainbow(account).bg(high_level_category_colors[account.split(":")[category_key_range].join(":")])
end

def colorize_amount amount
    Rainbow(amount).bg(amount.match(/([\d|\.|\-]+)/)[0].to_i > 0 ? :green : :red)
end

def generate_colored_category_list category_list
    category_key_range = journals_from_multiple_people? ? 0..2 : 0..1
    high_level_list = category_list.map{|c| c.split(":")[category_key_range].join(":")}.uniq
    high_level_category_colors = {}
    high_level_list.each_with_index {|c,i| high_level_category_colors[c] = COLORS[(i % COLORS.size)]}
    category_list.map {|c| colorize_account(c,high_level_category_colors, category_key_range)}
end

period_arg = CONFIG["starting_year"] ? ("--period '" + CONFIG["starting_year"] + "'") : ""
csv = CSV.new(`hledger --file import/all-years.journal #{period_arg} print unknown | hledger -f - register -I -O csv`).read

transactions = []
csv.each do |l|
    line = parse_csv_line(l)
    next if line[:index] == "txnidx"
    transactions.push(line) unless line[:account].include?("unknown")
end

category_rules = Dir.glob(CONFIG["rules_directories"]).map {|path| File.read(path).split("\n") }.flatten.delete_if {|t| t == "if|account2"}
other_accounts = File.read(CONFIG["accounts_list_file_path"]).split("\n") rescue []
category_list = category_rules.map{|c| c.split("|")[1]}.concat(other_accounts).uniq!.sort rescue other_accounts

colored_category_list = generate_colored_category_list(category_list)

loop do
    txns_list = transactions.map.with_index do |t,i|
        [t[:date], 
        colorize_description(t[:description],i),
        t[:account],
        colorize_amount(t[:amount])
        ].join("|") + "\n"
    end

    break if transactions.empty?
    txn_raw = `echo '#{txns_list.join}' | sk --ansi --header="Choose transaction" -d '|' --tac --case=ignore`
    break if txn_raw.empty?
    txn = txn_raw.split("|")
    txn_full = transactions.select{|t| t[:date] == txn[0] and t[:description] == txn[1]}.first

    category = `echo '#{colored_category_list.join("\n")}' | sk --ansi --header="Choose category"  --tac --case=ignore`.strip.split("\n")[0]
    break if category.nil?

    # IS THIS TXN SPECIFIC ? [Y]/N 
    question = "Do you want all transactions with #{txn_full[:description]} to be classified as #{category}?"
    specific_txn = `echo 'NO\nYES' | sk --header="#{question}" --ansi --print-cmd -i`.strip 
    break if specific_txn.empty?


    if specific_txn == "NO"
        comment = `echo '#{txn_raw}#{category}' | sk --header="Enter comment (prepend : to inhibit selection)" --ansi --print-cmd -i` 
        comment = comment.split("\n")[0]
        comment = nil if (comment == ":" or comment.empty?)
        rule = match_to_specific_if_block(account_txn_match(txn_full),category, comment)
        rules_file_path = account_to_spec_rules_file(txn_full[:account])
        transactions.delete_if{|t| t[:code] == txn_full[:code]}
    else
        rule = match_to_if_block(cleanup_description(txn_full[:description]),category)
        rules_file_path = category_to_rules_file(category)
        transactions.delete_if{|t| t[:description] == txn_full[:description]}
    end
    File.open(rules_file_path, "a+") {|f| f.write("\n"+rule)}
end


