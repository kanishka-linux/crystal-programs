require "benchmark"

BRACKETS = {
  "percent" => [0.10, 0.12, 0.22, 0.24, 0.32, 0.35, 0.37],
  "single"  => [0, 9875, 40125, 85525, 163300, 207350, 518400],
  "married" => [0, 19750, 80250, 171050, 326600, 414700, 622050],
  "hoh"     => [0, 14100, 53700, 85500, 163300, 207350, 518400],
}

# Initial Impression of the code:
# The below code (calc_taxes) cleverly uses various list manipulation
# techniques and calculates the tax in a few lines,
# but in the process it scans the list multiple times
# which impacts the performance.
# finding_index is O(n)
# The inner loop which seems to be just one simple loop with O(n)
# complexity has multiple parts
# bracket.first -> O(n)
# percentage.first -> O(n)
# zip(bracket.first, percentage.first) -> O(n)
# reverse -> O(n)
# even though overall it seems O(n) but there is a constant factor
# involved here which is 5 times n, which can surely degrade the
# performance atlease by 5 times compared to scanning the list just once.
def calc_taxes(income, status = "single")
  bracket = BRACKETS[status]
  percentages = BRACKETS["percent"]
  index = bracket.index { |high| income < high } || bracket.size
  total_taxes = 0
  bracket.first(index).zip(percentages.first(index)).reverse.each do |lower, percent|
    diff_to_lower = (income - lower)
    total_taxes += diff_to_lower * percent
    income -= diff_to_lower
  end
  total_taxes
end

#--------Refactored Code-----------------------#

SINGLE = {9875, 40125, 85525, 163300, 207350, 518400}
PERCENT = {0.10, 0.12, 0.22, 0.24, 0.32, 0.35, 0.37}
MARRIED = {19750, 80250, 171050, 326600, 414700, 622050}
HOH = {14100, 53700, 85500, 163300, 207350, 518400}

def calc_taxes_v2(income : Int32, status="single")
  intermediate_taxes = 0
  bracket_lower = 0

  case status
  when "single"
    bracket = SINGLE
  when "married"
    bracket = MARRIED
  else
    bracket = HOH
  end

  bracket.each_with_index do |bracket_upper, index|

    if income >= bracket_upper
        intermediate_taxes += (bracket_upper - bracket_lower) * PERCENT[index]
        bracket_lower = bracket_upper
        return intermediate_taxes if income == bracket_upper
    else
        final_tax = intermediate_taxes + (income - bracket_lower) * PERCENT[index]
        return final_tax
    end
  end
  
  final_tax = intermediate_taxes + (income - bracket[-1]) * PERCENT[bracket.size] 
  return final_tax
end

Benchmark.ips do |x|
  x.report("calc-tax") do
    calc_taxes(500_000_000)
  end

  x.report("calc-tax-v2") do
    calc_taxes_v2(500_000_000)
  end

  # calc-tax   4.58M (218.36ns) (± 2.37%)  576B/op  171.56× slower
  # calc-tax-v2 785.67M (  1.27ns) (± 2.15%)  0.0B/op         fastest
end


