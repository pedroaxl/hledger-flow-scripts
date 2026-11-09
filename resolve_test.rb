require 'rspec/autorun'
require_relative './src/resolve.rb'
require 'rainbow'
require 'tmpdir'

describe Resolve do
    let(:project_root) { File.expand_path('..', __dir__) }
    let(:import_glob) { File.join(project_root, 'import', '*') }

    it "cleans up the description" do
        expect(Resolve.cleanup_description("Something/else")).to eq('Something\/else')
        expect(Resolve.cleanup_description("Something +1234")).to eq('Something \+1234')
        expect(Resolve.cleanup_description("Something *1234")).to eq('Something \*1234')
        expect(Resolve.cleanup_description("Something/else")).to eq('Something\/else')
    end
    it "cleans up installments in the description" do
        expect(Resolve.cleanup_description("Latam Site 2/4")).to eq("Latam Site")
        expect(Resolve.cleanup_description("Latam Site 12/12")).to eq("Latam Site")
    end
    context "journals from multiple people" do
        before do 
            allow(Dir).to receive(:[]).with(import_glob).and_return(['/pedro','/livia'])
            allow(File).to receive(:directory?).with('/pedro').and_return(true)
            allow(File).to receive(:directory?).with('/livia').and_return(true)
        end
        it "journals from multiepl people should return false" do
            expect(Resolve.journals_from_multiple_people?).to be true
        end
        it "should convert account to rules file" do
            expect(Resolve.account_to_spec_rules_file("Liabilities:Lívia:Nubank:Cartão")).to eql(File.join(project_root, "import/livia/nubank/cartao/nubank-cartao-specific.rules"))
            expect(Resolve.account_to_spec_rules_file("Assets:Lívia:Nubank:Conta")).to eql(File.join(project_root, "import/livia/nubank/conta/nubank-conta-specific.rules"))
        end
        it "should convert expense account to rules file" do
            expect(Resolve.category_to_rules_file("Expenses:Lívia:Alimentação:Café")).to eql("./rules/livia/expenses.psv")
            expect(Resolve.category_to_rules_file("Income:Lívia:Salário")).to eql("./rules/livia/income.psv")
            expect(Resolve.category_to_rules_file("Temporary:Lívia:Payments")).to eql("./rules/livia/temporary.psv")
            expect(Resolve.category_to_rules_file("Expenses:Empresa:Alimentação:Café")).to eql("./rules/empresa/expenses.psv")
            expect(Resolve.category_to_rules_file("Income:Empresa:Salário")).to eql("./rules/empresa/income.psv")
        end
    end
    context "journals from one person" do
        before do 
            allow(Dir).to receive(:[]).with(import_glob).and_return(['/pedro'])
            allow(File).to receive(:directory?).with('/pedro').and_return(true)
        end
        it "journals from multiepl people should return false" do
            expect(Resolve.journals_from_multiple_people?).to be false
        end
        it "should convert account to specific rules file" do
            expect(Resolve.account_to_spec_rules_file("Liabilities:Credit Cards:Nubank:Mastercard")).to eql(File.join(project_root, "import/pedro/nubank/creditcard/nubank-creditcard-specific.rules"))
            expect(Resolve.account_to_spec_rules_file("Assets:Accounts:Nubank")).to eql(File.join(project_root, "import/pedro/nubank/account/nubank-account-specific.rules"))
        end
        it "should convert expense account to rules file" do
            expect(Resolve.category_to_rules_file("Expenses:Home:Rent")).to eql("./rules/expenses/home.psv")
            expect(Resolve.category_to_rules_file("Income:Benefits")).to eql("./rules/income.psv")
            expect(Resolve.category_to_rules_file("Assets:Savings:Bradesco")).to eql("./rules/savings.psv")
            expect(Resolve.category_to_rules_file("Assets:Temporary:FX")).to eql("./rules/temporary.psv")
        end
    end

    describe Resolve::Money do
      it "reads values below one correctly" do
        expect(Resolve::Money.value("R$0.50")).to eql(0.5)
        expect(Resolve::Money.value("R$-100")).to eql(-100.0)
      end
      it "formats with sign and thousands" do
        expect(Resolve::Money.present(10000.0, "R$")).to eql("+R$10.000,00")
        expect(Resolve::Money.present(-129.9, "R$")).to eql("-R$129,90")
        expect(Resolve::Money.present(0.5, "R$")).to eql("+R$0,50")
      end
      it "totals each commodity separately" do
        txns = [{amount: "R$-10.50"}, {amount: "R$-1.50"}, {amount: "USD-3.00"}]
        expect(Resolve::Money.totals(txns)).to eql([["R$", -12.0], ["USD", -3.0]])
      end
    end

    describe Resolve::Colorize do
      around do |example|
        previous = Rainbow.enabled
        Rainbow.enabled = true
        example.run
        Rainbow.enabled = previous
      end
      it "highlights only incoming amounts and never sets a background" do
        incoming = Resolve::Colorize.amount("+R$0,50")
        expect(incoming).to eql(Rainbow("+R$0,50").green.bold.to_s)
        expect(incoming).not_to match(/\e\[4[0-7]m/)
        expect(Resolve::Colorize.amount("-R$100,00")).to eql("-R$100,00")
      end
      it "bolds only the category group" do
        allow(Resolve).to receive(:journals_from_multiple_people?).and_return(false)
        list = Resolve::Colorize.generate_category_list(["Expenses:Home:Rent", "Income:Benefits"])
        expect(list).to eql(["#{Rainbow('Expenses:Home').bold}:Rent", Rainbow("Income:Benefits").bold.to_s])
      end
    end

    describe Resolve::Theme do
      it "prefers the configured value" do
        expect(Resolve::Theme.sk_color("molokai", omarchy_theme: "Catppuccin Latte", light: true)).to eql("molokai")
      end
      it "uses the sk theme matching the Omarchy theme" do
        expect(Resolve::Theme.sk_color(nil, omarchy_theme: "Catppuccin Latte\n", light: true)).to eql("catppuccin-latte")
      end
      it "falls back to light or dark" do
        expect(Resolve::Theme.sk_color(nil, omarchy_theme: "Outro", light: true)).to eql("light")
        expect(Resolve::Theme.sk_color(nil, omarchy_theme: nil, light: false)).to eql("dark")
      end
    end

    describe Resolve::Skim do
      it "reads a plain selection" do
        expect(Resolve::Skim.parse("7\tTexto\n")).to eql(Resolve::Skim::Choice.new(7, nil))
      end
      it "reads a selection made through a bound action" do
        expect(Resolve::Skim.parse("especifica\n3\tTexto\n")).to eql(Resolve::Skim::Choice.new(3, "especifica"))
      end
      it "reads an action with no selected row" do
        expect(Resolve::Skim.parse("desfazer\n")).to eql(Resolve::Skim::Choice.new(nil, "desfazer"))
      end
      it "treats empty output as cancelled" do
        expect(Resolve::Skim.parse("")).to be_nil
      end
      it "passes the header as one argument, without shell quoting" do
        command = Resolve::Skim.command(header: %q(Arko's "bar"), color: "light")
        expect(command).to include(%q(--header=Arko's "bar"), "--color=light")
      end
    end

    describe "grouping" do
      it "merges installments and case variants, largest group first" do
        txns = [
          {description: "Loja", amount: "R$-1.00"},
          {description: "Latam 2/4", amount: "R$-10.00"},
          {description: "LATAM 3/4", amount: "R$-10.00"}
        ]
        groups = Resolve.group_transactions(txns)
        expect(groups.map {|g| g[:description]}).to eql(["Latam", "Loja"])
        expect(groups.first[:transactions].size).to eql(2)
        expect(groups.first[:ambiguous]).to be false
      end
      it "lists each transfer on its own line, keeping them together" do
        txns = [
          {description: "Transferência Lívia", amount: "R$-100.00", date: "2026-08-01"},
          {description: "Mercado", amount: "R$-1.00", date: "2026-08-02"},
          {description: "Transferência Lívia", amount: "R$-50.00", date: "2026-08-03"}
        ]
        groups = Resolve.group_transactions(txns)
        expect(groups.map {|g| g[:description]}).to eql(["Transferência Lívia", "Transferência Lívia", "Mercado"])
        expect(groups.first(2).map {|g| g[:transactions].size}).to eql([1, 1])
        expect(groups.first[:siblings].size).to eql(2)
        expect(groups.first[:ambiguous]).to be true
      end
      it "also splits descriptions that already had different categories" do
        txns = [{description: "Débito em Conta", amount: "R$-1.00"}, {description: "Débito em Conta", amount: "R$-2.00"}]
        groups = Resolve.group_transactions(txns, Set["débito em conta"])
        expect(groups.size).to eql(2)
        expect(groups.all? {|g| g[:ambiguous]}).to be true
      end
    end

    describe Resolve::Hledger do
      let(:rows) do
        [
          %w[txnidx date code description account amount total],
          ["1", "2026-01-01", "", "Uber 1/2", "Liabilities:Card", "R$-10", "0"],
          ["1", "2026-01-01", "", "Uber 1/2", "Expenses:Taxi", "R$10", "0"],
          ["2", "2026-01-02", "", "Uber 2/2", "Liabilities:Card", "R$-10", "0"],
          ["2", "2026-01-02", "", "Uber 2/2", "Expenses:Taxi", "R$10", "0"],
          ["3", "2026-01-03", "", "Pix", "Assets:Bank", "R$-10", "0"],
          ["3", "2026-01-03", "", "Pix", "Expenses:Gifts", "R$10", "0"],
          ["4", "2026-01-04", "", "Pix", "Assets:Bank", "R$-10", "0"],
          ["4", "2026-01-04", "", "Pix", "Expenses:Family", "R$10", "0"]
        ]
      end
      let(:known) { Set["Liabilities:Card", "Expenses:Taxi", "Expenses:Gifts", "Expenses:Family"] }

      it "ignores the origin account of each transaction" do
        history = Resolve::Hledger.history_from_register(rows, known)
        expect(history.map {|e| e[:category]}).not_to include("Liabilities:Card")
      end
      it "flags only descriptions with more than one category, ignoring installments" do
        history = Resolve::Hledger.history_from_register(rows, known)
        expect(Resolve::Hledger.ambiguous_keys(history)).to eql(Set["pix"])
      end
    end

    describe Resolve::Similarity do
      let(:history) do
        [
          {description: "Claro Net", category: "Expenses:Home:Internet", count: 8, tokens: Resolve::Similarity.tokens("Claro Net")},
          {description: "Claro Celular", category: "Expenses:Home:Phone", count: 2, tokens: Resolve::Similarity.tokens("Claro Celular")},
          {description: "Padaria", category: "Expenses:Food", count: 5, tokens: Resolve::Similarity.tokens("Padaria")}
        ]
      end
      it "ignores generic words, accents and installments" do
        expect(Resolve::Similarity.tokens("Transferência Lívia Café 2/4")).to eql(["livia", "cafe"])
      end
      it "finds similar descriptions and ranks suggested categories" do
        similar = Resolve::Similarity.similar("Débito automático Claro", history)
        expect(similar.map {|e| e[:description]}).to eql(["Claro Net", "Claro Celular"])
        expect(Resolve::Similarity.suggestions(similar)).to eql([["Expenses:Home:Internet", 8], ["Expenses:Home:Phone", 2]])
      end
      it "does not match people who only share a surname" do
        relatives = [{description: "Pedro Axelrud", category: "Assets:Savings", count: 80, tokens: Resolve::Similarity.tokens("Pedro Axelrud")}]
        expect(Resolve::Similarity.similar("Silvio Axelrud", relatives)).to eql([])
      end
      it "returns nothing when only generic words remain" do
        expect(Resolve::Similarity.similar("Transferência", history)).to eql([])
      end
    end

    describe Resolve::RuleFile do
      around {|example| Dir.mktmpdir {|d| @dir = d; example.run}}
      let(:path) { File.join(@dir, "regras.psv") }

      it "appends and undoes a rule, keeping earlier content" do
        File.write(path, "if|account2\nA|B")
        entry = Resolve::RuleFile.append(path, "Çafé|X")
        expect(File.read(path)).to eql("if|account2\nA|B\nÇafé|X")
        Resolve::RuleFile.undo(entry)
        expect(File.read(path)).to eql("if|account2\nA|B")
      end
      it "removes a file created only for the undone rule" do
        entry = Resolve::RuleFile.append(path, "A|B")
        Resolve::RuleFile.undo(entry)
        expect(File.exist?(path)).to be false
      end
      it "refuses to undo when the file changed afterwards" do
        entry = Resolve::RuleFile.append(path, "A|B")
        File.write(path, "\nC|D", mode: "a")
        expect { Resolve::RuleFile.undo(entry) }.to raise_error(/mudou/)
        expect(File.read(path)).to eql("A|B\nC|D")
      end
      it "never leaves a blank line when the file already ends in a newline" do
        File.write(path, "if|account2\nA|B\n")
        entry = Resolve::RuleFile.append(path, "C|D")
        expect(File.read(path)).to eql("if|account2\nA|B\nC|D")
        Resolve::RuleFile.undo(entry)
        expect(File.read(path)).to eql("if|account2\nA|B\n")
      end
    end

    describe Resolve::Screen do
      let(:group) { {description: "Claro", transactions: [{date: "2026-08-01", description: "Claro", amount: "R$-129.90", account: "Assets:Accounts:Nubank"}]} }

      it "keeps the id hidden in the first field" do
        expect(Resolve::Screen.group_row(group, 4)).to start_with("4\t2026-08-01  Claro")
      end
      it "summarizes the group for the category screen" do
        expect(Resolve::Screen.group_summary(group)).to eql("Claro · 1 transação · -R$129,90 · Accounts:Nubank")
      end
      it "shows the date and swaps the keys for transactions that vary" do
        varying = group.merge(ambiguous: true, siblings: group[:transactions] * 3)
        expect(Resolve::Screen.group_row(varying, 1)).to include("•")
        expect(Resolve::Screen.group_summary(varying)).to eql("2026-08-01 · Claro · -R$129,90 · Accounts:Nubank")
        expect(Resolve::Screen.category_keys_hint(varying)).to start_with("Enter: só esta transação · Ctrl-G: regra geral (3 transações)")
      end
      it "keeps the general rule as default otherwise" do
        expect(Resolve::Screen.category_keys_hint(group.merge(ambiguous: false, siblings: group[:transactions]))).to start_with("Enter: regra geral (1 transação)")
      end
      it "puts suggested categories first, keeping real indexes" do
        rows = Resolve::Screen.category_rows(["A", "B", "C"], ["A", "B", "C"], [["C", 8]])
        expect(rows).to eql(["2\tC  ← 8x em parecidas", "0\tA", "1\tB"])
      end
      it "keeps comments from breaking the PSV" do
        expect(Resolve::Screen.clean_comment(" a|b \n")).to eql("a/b")
        expect(Resolve::Screen.clean_comment("\n")).to be_nil
        expect(Resolve::Screen.clean_comment(nil)).to be_nil
      end
    end

    describe Resolve::Hledger do
    end

    describe Resolve::Batch do
    end
end