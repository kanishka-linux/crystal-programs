require "lexbor"
require "http/client"
require "log"
require "benchmark"
require "regex"


# Initial impression of the code
# The module  seems to be fetching TLD and domain suffix related information from IANA and mozilla
# and then extracts domain or subdomain related information based on some logic.
# code review part
#-----------------
# 1. the information from mozilla/iana is actually fetched when invoking strip_subdomains/2 and strip_suffix/2.
# instead of fetching this information during initialization. It is good to have some kind of
# initializer function which during initialization fetches the info and store it in some variable. Since this
# information mostly remains static - it is fine to initialize it during start - instead of doing this in
# the actual core logic.
#----------------
# 2. When making HTTP call the code uses some kind of retry/backoff mechanism,
# actually this should be part of some middleware,
# which should be invoked automatically for every HTTP call, so that we  don't have to repeat the code
# everytime, and every function will be able to make use of this functionality.
#--------------
# 3. Initial code wasn't able to build and run due to dependencies issue with latest version of crystal.
# So need to modify the dependencies to use lexbor instead of myhtml and accordingly code was also modified.
#-------------------
# 4. Actual core logic of strip_subdomains/2 and strip_suffix/2:
# In these two functions most important thing is figuring out actual domain and TLD which is towards the end of
# hostname string, so starting from the end of the string (i.e. reverse) would make it more efficient to
# match the suffix quickly and extract relevant substring thereafter.
#------------------
# 5. About the parameter `tld_only` -> not able to understand how the code uses it actually.
# When tld_only=true, it updates self.tld_extensions, but after that this variable is never used
# anywhere in the code. So not sure what is does. Having some examples with input and output
# when tld_only=true - would have helped to understand the actual logic better.
#------------------


# Initial code,  I've replaced myhtml to lexbor - for comparison between old and new code.
module DomainUtil
  Log = ::Log.for("DomainUtil")
  class_getter tld_extensions : Set(String) = Set(String).new

  class_getter suffixes : Set(String) = Set(String).new

  class_property retry_count : Int32 = 5

  class_property backoff_time : Time::Span = 0.2.seconds

  class_property backoff_factor : Float64 = 1.5

  TLD_URL = "https://www.iana.org/domains/root/db"

  SUFFIX_URL = "https://publicsuffix.org/list/public_suffix_list.dat"

  def self.update_tlds(retry_count : Int32 = self.retry_count, backoff_time : Time::Span = self.backoff_time, backoff_factor : Float64 = self.backoff_factor)
    Log.info { "downloading TLD database from IANA..." }
    response = HTTP::Client.get(TLD_URL)
    if response.status_code != 200
      if retry_count > 0
        Log.warn { "#{TLD_URL} returned a non-200 status code (#{response.status_code}), retrying in #{backoff_time.total_seconds}s" }
        sleep backoff_time
        return self.update_tlds(retry_count - 1, backoff_time * backoff_factor)
      end
      raise "could not access #{TLD_URL} after several retries, status_code: #{response.status_code}"
    end
    lexbor = Lexbor::Parser.new(response.body)
    @@tld_extensions = lexbor.css("span.domain.tld > a").map(&.inner_text[1..]).to_set
    Log.info { "successfully loaded #{self.tld_extensions.size} top level domain extensions from IANA" }
  end

  def self.update_suffixes(retry_count : Int32 = self.retry_count, backoff_time : Time::Span = self.backoff_time, backoff_factor : Float64 = self.backoff_factor)
    Log.info { "downloading public suffixes database from mozilla..." }
    response = HTTP::Client.get(SUFFIX_URL)
    if response.status_code != 200
      if retry_count > 0
        Log.warn { "#{SUFFIX_URL} returned a non-200 status code (#{response.status_code}), retrying in #{backoff_time.total_seconds}s" }
        sleep backoff_time
        return self.update_suffixes(retry_count - 1, backoff_time * backoff_factor)
      end
      raise "could not access #{SUFFIX_URL} after several retries, status_code: #{response.status_code}"
    end
    @@suffixes = response.body.lines.map(&.strip).reject { |line| line.starts_with?("/") || line.empty? }
      .map { |ext| ext.starts_with?("*") ? ext[1..] : ext }.to_set
    Log.info { "successfully loaded #{self.suffixes.size} domain suffixes from mozilla" }
  end

  def self.strip_subdomains(hostname : String, tld_only = false) : String
    set = tld_only ? self.tld_extensions : self.suffixes
    (tld_only ? self.update_tlds : self.update_suffixes) if set.empty?
    tokens = hostname.downcase.split(".")
    (0..(tokens.size - 1)).each do |i|
      extension = tokens[i..].join(".")
      return tokens[(i-1)..].join(".") if self.suffixes.includes?(extension)
    end
    return hostname.downcase
  end

  def self.strip_suffix(hostname : String, tld_only = false) : String
    set = tld_only ? self.tld_extensions : self.suffixes
    (tld_only ? self.update_tlds : self.update_suffixes) if set.empty?
    tokens = hostname.downcase.split(".")
    (0..(tokens.size - 1)).each do |i|
      extension = tokens[i..].join(".")
      return tokens[0..(i - 1)].join(".") if self.suffixes.includes?(extension)
    end
    return hostname.downcase
  end
end

#---------------Refactored Code with Improved Performance------------------#
module DomainUtilV2
  Log = ::Log.for("DomainUtilV2")
  class_getter tld_extensions : Set(String) = Set(String).new

  class_getter suffixes : Set(String) = Set(String).new

  class_getter suffixes_hash : Hash(String, Bool) = {} of String => Bool

  class_property retry_count : Int32 = 5

  class_property backoff_time : Time::Span = 0.2.seconds

  class_property backoff_factor : Float64 = 1.5

  class_getter splitted_domain : Hash(String, Array(String)) = {} of String => Array(String)

  TLD_URL = "https://www.iana.org/domains/root/db"

  SUFFIX_URL = "https://publicsuffix.org/list/public_suffix_list.dat"

  def self.update_tlds(retry_count : Int32 = self.retry_count, backoff_time : Time::Span = self.backoff_time, backoff_factor : Float64 = self.backoff_factor)
    Log.info { "downloading TLD database from IANA..." }
    response = HTTP::Client.get(TLD_URL)
    if response.status_code != 200
      if retry_count > 0
        Log.warn { "#{TLD_URL} returned a non-200 status code (#{response.status_code}), retrying in #{backoff_time.total_seconds}s" }
        sleep backoff_time
        return self.update_tlds(retry_count - 1, backoff_time * backoff_factor)
      end
      raise "could not access #{TLD_URL} after several retries, status_code: #{response.status_code}"
    end
    lexbor = Lexbor::Parser.new(response.body)
    @@tld_extensions = lexbor.css("span.domain.tld > a").map(&.inner_text[1..]).to_set
    Log.info { "successfully loaded #{self.tld_extensions.size} top level domain extensions from IANA" }
  end

  def self.update_suffixes(retry_count : Int32 = self.retry_count, backoff_time : Time::Span = self.backoff_time, backoff_factor : Float64 = self.backoff_factor)
    Log.info { "downloading public suffixes database from mozilla..." }
    response = HTTP::Client.get(SUFFIX_URL)
    if response.status_code != 200
      if retry_count > 0
        Log.warn { "#{SUFFIX_URL} returned a non-200 status code (#{response.status_code}), retrying in #{backoff_time.total_seconds}s" }
        sleep backoff_time
        return self.update_suffixes(retry_count - 1, backoff_time * backoff_factor)
      end
      raise "could not access #{SUFFIX_URL} after several retries, status_code: #{response.status_code}"
    end
    @@suffixes = response.body.lines.map(&.strip).reject { |line| line.starts_with?("/") || line.empty? }
      .map { |ext| ext.starts_with?("*") ? ext[1..] : ext }.to_set
    Log.info { "successfully loaded #{self.suffixes.size} domain suffixes from mozilla" }
  end

  def self.strip_subdomains(hostname : String, tld_only = false) : String
        
    set = tld_only ? self.tld_extensions : self.suffixes
    (tld_only ? self.update_tlds : self.update_suffixes) if set.empty?

    host_name = hostname.downcase.split(".")

    # splitting of hostname string is the costliest
    # operation in this program, if we cache this
    # like below then it increases program
    # speed by almost 40-50x for the input
    # given below. This  looks like cheating for this exercise,
    # but in real-world scenarios caching the pre-computed
    # result is often needed to improve performance
    # if the same request is fired again and again.
    #----------------------------------------------
    #if self.splitted_domain.has_key?(hostname)
    #    host_name  =  self.splitted_domain[hostname]
    #else
    #    host_name = hostname.downcase.split(".")
    #    self.splitted_domain[hostname] = host_name 
    #end
    #----------------------------------------------
    
    res = ""
    host_name.reverse!.each do |token|
        res = (res == "") ? token : "#{token}.#{res}"
        self.suffixes.includes?(res) ? next : return res
    end

    return res
  end

  def self.strip_suffix(hostname : String, tld_only = false) : String
     set = tld_only ? self.tld_extensions : self.suffixes
    (tld_only ? self.update_tlds : self.update_suffixes) if set.empty?
 
    
    host_name = hostname.downcase.split(".")

    # splitting of hostname string is the costliest
    # operation in this program, if we cache this
    # like below then it increases program
    # speed by almost 12-15x for the input
    # given below. This  looks like cheating for this exercise,
    # but in real-world scenarios caching the pre-computed
    # result is often needed to improve performance
    # if the same request is fired again and again.
    #----------------------------------------------
    #if self.splitted_domain.has_key?(hostname)
    #    host_name  =  self.splitted_domain[hostname]
    #else
    #    host_name = hostname.downcase.split(".")
    #    self.splitted_domain[hostname] = host_name 
    #end
    #----------------------------------------------

    suffix_to_match = ""
    suffix_to_remove = ""

    host_name.reverse!.each do |token|
        if (suffix_to_match == "")
            suffix_to_match = token
        else
            suffix_to_match = "#{token}.#{suffix_to_match}"
        end

        if self.suffixes.includes?(suffix_to_match)
            suffix_to_remove = suffix_to_match
        else
            return hostname.sub(".#{suffix_to_remove}", "")
        end
    end

    return hostname.downcase
  end
end


# Benchmarking on just one input doesn't give the accurate estimate.
# The program performance varies based on the length/size of the hostname/domain.
# We need some kind of property based testing/benchmarking framework
# that can randomly generate strings of varying length for hostname
# and give some average result for varying input.
# For now, I've taken arbitrary large domain name to see how the program
# performs as the length of input increases.
Benchmark.ips do |x|
  x.report("original-strip-domains") do
      DomainUtil.strip_subdomains("gpt.know.what.map.service.location.open.try.web.now.blog.example.com")
  end

  x.report("new-strip-domains") do
      DomainUtilV2.strip_subdomains("gpt.know.what.map.service.location.open.try.web.now.blog.example.com")
  end
  # original-strip-domains 333.21k (  3.00µs) (± 0.76%)  2.99kB/op   4.48× slower
  # new-strip-domains   1.49M (670.33ns) (± 1.66%)    976B/op        fastest
end

Benchmark.ips do |x|
  x.report("original-strip-suffix") do
      DomainUtil.strip_suffix("gpt.fast.quick.more.know.what.map.service.location.open.try.web.now.blog.example.com")
  end

  x.report("new-strip-suffix") do
      DomainUtilV2.strip_suffix("gpt.fast.quick.more.know.what.map.service.location.open.try.web.now.blog.example.com")
  end
  # original-strip-suffix 236.46k (  4.23µs) (± 0.77%)  4.01kB/op   4.15× slower
  # new-strip-suffix 980.97k (  1.02µs) (± 1.68%)  1.28kB/op        fastest
end
