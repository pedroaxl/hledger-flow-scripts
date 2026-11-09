require 'i18n'
require 'rainbow'
require 'csv'
require 'json'
require 'set'
require 'shellwords'


I18n.available_locales = [:en]


class Resolve

  INSTALLMENT_SUFFIX = /\s*(?<!\d)\d{1,2}\/\d{1,2}$/

  def self.strip_installment(desc)
    desc.sub(INSTALLMENT_SUFFIX, "").strip
  end

  def self.cleanup_description(desc)
    strip_installment(desc).gsub("*",'\*').gsub("\+", '\\\+').gsub(/\//,'\/')
  end

  def self.journals_from_multiple_people?  
    project_root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
    Dir[File.join(project_root, 'import', '*')].map{|p| File.directory?(p)}.count(true) > 1
  end

  def self.account_to_spec_rules_file account
    account_parsed = account.split(':')
    bank_name = I18n.transliterate(account_parsed[2]).downcase
    if Resolve.journals_from_multiple_people? 
        person_name = I18n.transliterate(account_parsed[1]).downcase
        account_name = I18n.transliterate(account_parsed[3].gsub(" ","")).downcase
    else
        # Encontrar diretório da pessoa procurando a partir da raiz do projeto
        project_root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
        person_name = I18n.transliterate(Dir[File.join(project_root, 'import', '*')].filter{|p| File.directory?(p)}.first.split("/").last)
        account_name = I18n.transliterate(account_parsed[1].gsub(" ","")).downcase
        account_name.chop! if account_name[-1] == "s" # remove plural
    end
    project_root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
    File.join(project_root, "import", person_name, bank_name, account_name, "#{bank_name}-#{account_name}-specific.rules")
  end

  def self.category_to_rules_file category
    c = category.split(":")
    if Resolve.journals_from_multiple_people?
      "./rules/#{I18n.transliterate(c[1]).downcase}/#{c[0].downcase}.psv"
    else
      if c[0] == "Assets" && %w[Savings Temporary].include?(c[1])
        "./rules/#{c[1].downcase}.psv"
      elsif c.size == 2
        "./rules/#{c[0].downcase}.psv"
      else
        "./rules/#{c[0].downcase}/#{I18n.transliterate(c[1]).downcase}.psv"
      end
    end
  end

  class Money
    def self.value(amount)
      amount.gsub(/[^\d.\-]/, "").to_f
    end

    def self.commodity(amount)
      amount.gsub(/[\d.,\-\s]/, "")
    end

    def self.present(value, commodity)
      sign = value > 0 ? "+" : (value < 0 ? "-" : "")
      integer, cents = ("%.2f" % value.abs).split(".")
      "#{sign}#{commodity}#{integer.reverse.scan(/\d{1,3}/).join('.').reverse},#{cents}"
    end

    # [[commodity, soma], ...] porque um grupo pode misturar R$ e USD
    def self.totals(transactions)
      transactions.group_by {|t| commodity(t[:amount])}.map do |c, txns|
        [c, txns.sum {|t| value(t[:amount])}]
      end
    end
  end

  # Só cor de texto, nunca de fundo: fundo sem definir o texto fica ilegível em tema claro.
  class Colorize
    def self.amount(text)
      text.start_with?("+") ? Rainbow(text).green.bold.to_s : text
    end

    def self.category(category, key_range)
      parts = category.split(":")
      group = Rainbow(parts[key_range].join(":")).bold.to_s
      rest = Array(parts[(key_range.end + 1)..])
      rest.empty? ? group : "#{group}:#{rest.join(':')}"
    end

    def self.generate_category_list category_list
      key_range = Resolve.journals_from_multiple_people? ? 0..2 : 0..1
      category_list.map {|c| category(c, key_range)}
    end
  end

  class Theme
    SK_BUILTIN = %w[catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha molokai]
    OMARCHY_THEME_DIR = File.expand_path("~/.local/state/omarchy/current/theme")

    # Ordem: sk_color do config.yml > tema do Omarchy embutido no sk > claro/escuro
    def self.sk_color(configured = nil, omarchy_theme: current_omarchy_theme, light: light_mode?)
      return configured if configured
      slug = omarchy_theme.to_s.strip.downcase.gsub(" ", "-")
      return slug if SK_BUILTIN.include?(slug)
      light ? "light" : "dark"
    end

    def self.current_omarchy_theme
      IO.popen(["omarchy", "theme", "current"], err: File::NULL, &:read)
    rescue SystemCallError
      nil
    end

    def self.light_mode?
      File.exist?(File.join(OMARCHY_THEME_DIR, "light.mode"))
    end
  end

  # Fala com o sk sem shell: descrições com ' ou " não quebram mais o comando.
  # Cada linha é "id\ttexto visível"; o id fica oculto por --with-nth.
  class Skim
    Choice = Struct.new(:id, :action)

    def self.command(header:, color:, binds: [], preview: nil)
      args = ["sk", "--ansi", "--delimiter=\t", "--with-nth=2..", "--layout=reverse",
              "--case=ignore", "--color=#{color}", "--header=#{header}"]
      args << "--bind=#{binds.join(',')}" unless binds.empty?
      args.push("--preview=#{preview}", "--preview-window=down:35%") if preview
      args
    end

    def self.parse(output)
      lines = output.split("\n")
      return nil if lines.empty?
      item = lines.find {|l| l.include?("\t")}
      action = lines.first.include?("\t") ? nil : lines.first
      Choice.new(item && item.split("\t").first.to_i, action)
    end

    def self.pick(rows, **options)
      output = IO.popen(command(**options), "r+") do |io|
        begin
          io.write(rows.join("\n"))
        rescue Errno::EPIPE
          # sk já fechou (Esc antes de ler tudo)
        end
        io.close_write
        io.read
      end
      parse(output)
    end
  end

  class Similarity
    STOPWORDS = %w[transferencia pagamento pgto debito automatico compra boleto recebida enviada pix para das dos com ltda]

    def self.tokens(description)
      I18n.transliterate(Resolve.strip_installment(description)).downcase.scan(/[a-z]{3,}/).uniq - STOPWORDS
    end

    def self.similar(description, history, limit: 8)
      query = tokens(description)
      return [] if query.empty?
      scored = history.filter_map do |entry|
        score = (query & entry[:tokens]).size.to_f / query.size
        entry.merge(score: score) if score > 0.5
      end
      scored.sort_by {|e| [-e[:score], -e[:count], e[:description]]}.first(limit)
    end

    # [[categoria, transações parecidas], ...], a mais usada primeiro
    def self.suggestions(similar_entries, limit: 3)
      counts = similar_entries.group_by {|e| e[:category]}.map {|c, es| [c, es.sum {|e| e[:count]}]}
      counts.sort_by {|c, n| [-n, c]}.first(limit)
    end
  end

  class RuleFile
    def self.append(path, rule)
      created = !File.exist?(path)
      # Linha em branco encerra a tabela "if" do hledger; só separa se faltar quebra de linha.
      needs_newline = !created && !File.zero?(path) && !File.binread(path).end_with?("\n")
      text = needs_newline ? "\n" + rule : rule
      File.open(path, "a") {|f| f.write(text)}
      {path: path, text: text, created: created}
    end

    # Grava várias regras como uma só operação: se uma falhar, nenhuma fica.
    def self.append_all(rules)
      appended = []
      rules.each {|path, rule| appended << append(path, rule)}
      appended
    rescue
      undo_all(appended)
      raise
    end

    def self.undo_all(entries)
      entries.reverse_each {|entry| undo(entry)}
    end

    # Só desfaz se a regra ainda for o fim do arquivo; nunca apaga outra edição.
    def self.undo(entry)
      content = File.binread(entry[:path])
      raise "#{entry[:path]} mudou depois de salvar a regra" unless content.end_with?(entry[:text].b)
      File.truncate(entry[:path], content.bytesize - entry[:text].bytesize)
      File.delete(entry[:path]) if entry[:created] && File.zero?(entry[:path])
    end
  end

  class Screen
    DESCRIPTION_WIDTH = 44
    AMOUNT_WIDTH = 15
    AMBIGUITY_CATEGORIES_SHOWN = 3
    AMBIGUOUS_LEGEND = "• Enter vale só para a transação da linha (a categoria pode variar)"

    def self.count_label(n)
      n == 1 ? "1 transação" : "#{n} transações"
    end

    def self.truncate(text, width)
      text.size > width ? text[0, width - 1] + "…" : text
    end

    def self.short_account(account)
      account.split(":").last(2).join(":")
    end

    def self.group_account(transactions)
      accounts = transactions.map {|t| t[:account]}.uniq
      accounts.size == 1 ? short_account(accounts.first) : "#{accounts.size} contas"
    end

    def self.amount_text(transactions)
      Money.totals(transactions).map {|c, v| Money.present(v, c)}
    end

    def self.amount_cell(transactions)
      texts = amount_text(transactions)
      padding = " " * [AMOUNT_WIDTH - texts.join(" ").size, 0].max
      padding + texts.map {|t| Colorize.amount(t)}.join(" ")
    end

    def self.description_cell(description)
      truncate(description, DESCRIPTION_WIDTH).ljust(DESCRIPTION_WIDTH)
    end

    def self.group_row(group, id)
      txns = group[:transactions]
      date = txns.map {|t| t[:date]}.max
      count = group[:ambiguous] ? "•" : "#{txns.size}x"
      "#{id}\t#{date}  #{description_cell(group[:description])}  #{count.rjust(4)}  #{amount_cell(txns)}  #{group_account(txns)}"
    end

    def self.transaction_row(txn, id)
      "#{id}\t#{txn[:date]}  #{description_cell(txn[:description])}  #{amount_cell([txn])}  #{short_account(txn[:account])}"
    end

    def self.category_rows(categories, colored, suggestions)
      suggested = suggestions.to_h
      ordered = categories.each_index.sort_by {|i| suggested.key?(categories[i]) ? [0, -suggested[categories[i]], i] : [1, 0, i]}
      ordered.map do |i|
        n = suggested[categories[i]]
        "#{i}\t#{colored[i]}#{n ? "  ← #{n}x em parecidas" : ""}"
      end
    end

    def self.group_summary(group)
      txns = group[:transactions]
      return [txns.first[:date], group[:description], amount_text(txns).join(" "), group_account(txns)].join(" · ") if group[:ambiguous]
      [group[:description], count_label(txns.size), amount_text(txns).join(" "), group_account(txns)].join(" · ")
    end

    def self.category_keys_hint(group)
      general = "regra geral (#{count_label(group[:siblings].size)})"
      if group[:ambiguous]
        "Enter: só esta transação · Ctrl-G: #{general} · Esc: voltar"
      else
        "Enter: #{general} · Ctrl-S: só uma transação · Esc: voltar"
      end
    end

    def self.transaction_picker_header(category, group)
      ["Aplicar #{category} a qual transação?",
       "Enter: só a selecionada · Ctrl-A: todas as #{group[:transactions].size} daqui, sem regra para as futuras · Esc: voltar"].join("\n")
    end

    def self.ambiguity_hint(group, categories_by_key)
      return nil unless group[:ambiguous]
      reason = if group[:description].match?(TRANSFER_DESCRIPTION)
        "cada transferência pode ter um motivo"
      else
        categories = categories_by_key.fetch(Resolve.description_key(group[:description]), [])
        shown = categories.first(AMBIGUITY_CATEGORIES_SHOWN).map {|c| short_account(c)}
        extra = categories.size - shown.size
        "já teve #{categories.size} categorias (#{shown.join(", ")}#{extra > 0 ? " e mais #{extra}" : ""})"
      end
      "• Enter vale só para esta transação: #{reason}"
    end

    def self.preview(group, similar_entries, hint = nil)
      lines = hint ? [hint, ""] : []
      lines << "Nesta classificação"
      group[:transactions].each do |t|
        lines << "  #{t[:date]}  #{amount_text([t]).first.rjust(AMOUNT_WIDTH)}  #{t[:description]}  (#{short_account(t[:account])})"
      end
      lines << "" << "Parecidas já classificadas"
      lines << "  nenhuma" if similar_entries.empty?
      similar_entries.each {|e| lines << "  #{"#{e[:count]}x".rjust(4)}  #{e[:category]}  ←  #{e[:description]}"}
      lines.join("\n") + "\n"
    end

    def self.preview_command(directory, name)
      "cat #{Shellwords.escape(directory)}/#{name}.txt"
    end

    def self.clean_comment(input)
      comment = input.to_s.strip.tr("|", "/")
      comment.empty? ? nil : comment
    end
  end

  class Hledger
    def self.get_unknown_transactions starting_year=nil
      period_arg = starting_year ? ("--period '" + starting_year + "'") : ""
      CSV.new(`hledger --file import/all-years.journal #{period_arg} print unknown | hledger -f - register -I -O csv`).read
    end

    def self.generate_category_list rules_directories, accounts_list_file_path
      category_rules = Dir.glob(rules_directories).map {|path| File.read(path).split("\n") }.flatten.delete_if {|t| t == "if|account2"}
      other_accounts = File.read(accounts_list_file_path).split("\n") rescue []
      category_list = category_rules.map{|c| c.split("|")[1]}.concat(other_accounts).uniq!.sort rescue other_accounts
    end

    # Como descrições já foram classificadas, para sugerir categorias
    def self.categorized_history categories
      known = categories.to_set
      rows = CSV.parse(IO.popen(["hledger", "--file", "import/all-years.journal", "register", "-O", "csv"], &:read))
      history_from_register(rows, known)
    end

    # A primeira postagem de cada transação é a conta de origem (banco/cartão), não a categoria.
    def self.history_from_register rows, known
      origin_seen = Set.new
      counts = Hash.new(0)
      rows.drop(1).each do |l|
        next if origin_seen.add?(l[0])
        counts[[l[3], l[4]]] += 1 if known.include?(l[4])
      end
      counts.map do |(description, category), count|
        {description: description, category: category, count: count, tokens: Similarity.tokens(description)}
      end
    end

    # Descrições que já receberam mais de uma categoria
    def self.ambiguous_keys history
      categories_by_key(history).select {|_, categories| categories.size > 1}.keys.to_set
    end

    # Categorias já usadas em cada descrição, da mais frequente para a menos frequente
    def self.categories_by_key history
      history.group_by {|e| Resolve.description_key(e[:description])}.transform_values do |entries|
        entries.group_by {|e| e[:category]}.sort_by {|_, same| -same.sum {|e| e[:count]}}.map(&:first)
      end
    end
  end

  TRANSFER_DESCRIPTION = /\Atransfer/i

  def self.description_key(description)
    strip_installment(description).downcase
  end

  # Uma linha por estabelecimento; o que resolve mais transações vem primeiro.
  # Descrições cuja categoria varia viram uma linha por transação, lado a lado.
  def self.group_transactions transactions, ambiguous_keys = Set.new
    groups = transactions.group_by {|t| description_key(t[:description])}.flat_map do |key, siblings|
      description = strip_installment(siblings.first[:description])
      if description.match?(TRANSFER_DESCRIPTION) || ambiguous_keys.include?(key)
        siblings.map {|t| {description: description, transactions: [t], siblings: siblings, ambiguous: true}}
      else
        [{description: description, transactions: siblings, siblings: siblings, ambiguous: false}]
      end
    end
    groups.each_with_index.sort_by do |g, i|
      [-g[:siblings].size, -g[:siblings].sum {|t| Money.value(t[:amount]).abs}, g[:description], i]
    end.map(&:first)
  end

  def self.parse_csv_line(l)
    {"index": l[0], "date": l[1], "code":l[2], "description":l[3], "account": l[4], "amount":l[5], "type": (l[5].gsub("R$","").to_f > 0 ? :credit : :debit) }
  end

  def self.generate_transactions_from_csv csv
    transactions = []
    csv.each do |l|
      line = parse_csv_line(l)
      next if line[:index] == "txnidx"
      transactions.push(line) unless line[:account].include?("unknown")
    end
    transactions
  end

  def self.match_to_specific_if_block(txn, account, comment)
    comment_str = comment.nil? ? "" : comment
    "#{txn[:code]}|#{account}|#{comment_str}"
  end

  def self.match_to_if_block(match_str, account)
    "#{match_str}|#{account}"
  end

  # batch processing methods

  class Batch
    def self.group_transactions_by_date transactions
      txns_grouped = transactions.group_by {|t| [t[:date], t[:account], t[:type]]}
      txns_grouped.map do |date_account_type, txns|
        {"date":date_account_type[0], "account": date_account_type[1], "type": date_account_type[2], "count": txns.count, "amount": txns.sum{|t| t[:amount].gsub("R$","").to_f}}
      end
    end

    def self.generate_grouped_transactions_list_for_loop transactions
      transactions.filter{|t| t[:count] > 5}.map do |t|
        [t[:date],t[:account],t[:type], "count: "+ t[:count].to_s, "amount: " + t[:amount].to_s].join("|") + "\n"
      end
    end

    def self.filter_transactions_from_date_type transactions, query_string
      q = query_string.split("|")
      transactions.filter{|t| t[:date] == q[0] and t[:account] == q[1] and t[:type] == q[2].to_sym}
    end

    def self.summary_message query_string, category
      q = query_string.split("|")
      [ "\nAre you sure?\n\n",
      "######## SUMMARY #########\n",
      "Date: #{q[0]}\n",
      "Account: #{q[1]}\n",
      "Type: #{q[2]}\n",
      (q[3].capitalize + "\n"),
      q[4].capitalize.strip + "\n",
      "Category: #{category.strip}\n"
    ].reverse
    end
  end

end