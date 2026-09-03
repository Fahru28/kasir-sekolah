module ApplicationHelper
  include Pagy::Frontend  # Pagination - provides pagy_nav() and other view helpers

  def rupiah(n)
    number_to_currency(n.to_i, unit: "Rp ", delimiter: ".", separator: ",", precision: 0)
  end

  def terbilang(n)
    n = n.to_i
    return "nol" if n == 0
    satuan = %w["" satu dua tiga empat lima enam tujuh delapan sembilan sepuluh sebelas]
    satuan = ["", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh", "delapan", "sembilan", "sepuluh", "sebelas"]
    if n < 12
      satuan[n]
    elsif n < 20
      terbilang(n - 10) + " belas"
    elsif n < 100
      terbilang(n / 10) + " puluh" + (n % 10 == 0 ? "" : " " + terbilang(n % 10))
    elsif n < 200
      "seratus" + (n % 100 == 0 ? "" : " " + terbilang(n % 100))
    elsif n < 1000
      terbilang(n / 100) + " ratus" + (n % 100 == 0 ? "" : " " + terbilang(n % 100))
    elsif n < 2000
      "seribu" + (n % 1000 == 0 ? "" : " " + terbilang(n % 1000))
    elsif n < 1_000_000
      terbilang(n / 1000) + " ribu" + (n % 1000 == 0 ? "" : " " + terbilang(n % 1000))
    elsif n < 1_000_000_000
      terbilang(n / 1_000_000) + " juta" + (n % 1_000_000 == 0 ? "" : " " + terbilang(n % 1_000_000))
    else
      n.to_s
    end
  end
end
