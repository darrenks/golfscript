#!/usr/bin/env ruby

# (c) Copyright 2008 Darren Smith.
# MIT License.

args = ARGV
if (i=ARGV.index("--"))
  gs_args = args[i+1..-1]
  args = args[0,i]
else
  gs_args = []
end

def usage
  STDERR.puts "usage: ruby #$0 filename.gs? options*
    filename.gs to run file or omit for interactive
    -q: no implicit output
    -n: no \"\#{ruby code eval}\"
    -r: int -1 ? generates rational instead of float
    --: all following args are problem input (single array of strings on stack, no STDIN)"
  exit(1)
end

options,filenames = args.partition{|arg|arg[0]=="-"}
RationalOption = options.include? "-r"
QuineOption = options.include? "-q"
NoInterpolationOption = options.include? "-n"

AllowedOptions = %w"r q n"
unknown_options = options.reject{|option|AllowedOptions.include? option[1..-1]}
if !unknown_options.empty?
  STDERR.puts "unknown options %p" % [unknown_options]
  usage
end

if filenames.size > 1
  STDERR.puts "multiple filenames present, there can only be one %p" % [filenames]
  usage
end

if defined? Encoding
  Encoding.default_external="ASCII-8BIT"
end

LB = []

# Make these still work for non integers on newer ruby versions too
class Integer
  alias orig_union |
  alias orig_inter &
  alias orig_xor ^
  def |(b); orig_union b.to_i end
  def &(b); orig_inter b.to_i end
  def ^(b); orig_xor b.to_i end
end
class Numeric
  def |(b); to_i.orig_union b end
  def &(b); to_i.orig_inter b end
  def ^(b); to_i.orig_xor b end
  def ~; ~to_i end
end

GIntId = 0
GArrayId = 1
GStringId = 2
GBlockId = 3

class Gtype
  def initialize_copy(other); @val = other.val.dup; end
  attr_reader :val
  def addop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.addop(b)) : factory(@val + rhs.val); end
  def subop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.subop(b)) : factory(@val - rhs.val); end
  def uniop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.uniop(b)) : factory(@val | rhs.val); end
  def intop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.intop(b)) : factory(@val & rhs.val); end
  def difop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.difop(b)) : factory(@val ^ rhs.val); end
  def ==(rhs); rhs.class_id!=GIntId && @val==rhs.val; end
  def eql?(rhs); rhs.class_id!=GIntId && @val==rhs.val; end
  def hash; @val.hash; end
  def <=>(rhs); @val<=>rhs.val; end
  def notop; self.falsey ? 1 : 0; end
end

class Numeric
  def class_id; GIntId; end
  def is_garray; false; end
  def unsafe_assignment; false; end
  def addop(rhs); rhs.is_a?(Numeric) ? self + rhs : (a,b=gscoerce(rhs); a.addop(b)); end
  def subop(rhs); rhs.is_a?(Numeric) ? self - rhs : (a,b=gscoerce(rhs); a.subop(b)); end
  def uniop(rhs); rhs.is_a?(Numeric) ? self | rhs : (a,b=gscoerce(rhs); a.uniop(b)); end
  def intop(rhs); rhs.is_a?(Numeric) ? self & rhs : (a,b=gscoerce(rhs); a.intop(b)); end
  def difop(rhs); rhs.is_a?(Numeric) ? self ^ rhs : (a,b=gscoerce(rhs); a.difop(b)); end
  def to_gs; Gstring.new(to_s); end
  def ginspect; to_gs; end
  def go; Stack<<self; end
  def notop; self == 0 ? 1 : 0; end
  def falsey; self == 0; end
  def ltop(rhs); self < rhs ? 1 : 0; end
  def gtop(rhs); self > rhs ? 1 : 0; end
  def equalop(rhs); self == rhs ? 1 : 0; end
  if RationalOption
    def question(b)
      (b<0 && equal?(1) ? 1r : self) ** b
    end
  else
    def question(b)
      self**(b<0 ? b.to_f : b)
    end
  end
  def leftparen; Stack<<self-1; end
  def rightparen; Stack<<self+1; end
  def gscoerce(b)
    c = b.class_id
    [if c == 1
      Garray.new([self])
    elsif c == 2
      to_gs
    else #Gblock
      to_gs.to_s.compile
    end,b]
  end
  def base(a)
    if a.is_garray
      r=0
      a.val.each{|i|
        r*=self
        r+=i
      }
      r
    else
      i=a.abs
      r=[]
      while i!=0
        r.unshift(i % self)
        i/=self
      end
      Garray.new(r)
    end
  end
  def comma
    Garray.new([*0...self])
  end
end

class Garray < Gtype
  def initialize(a)
    @val = a || []
  end
  def is_garray; true; end
  def unsafe_assignment; false; end
  def concat(rhs)
    if rhs.class != self.class
      a,b=gscoerce(rhs)
      a.addop(b)
    else
      @val.concat(rhs.val)
      self
    end
  end
  def factory(a)
    Garray.new(a)
  end
  def to_gs
    r = []
    @val.each {|i| r.concat(i.to_gs.val) }
    Gstring.new(r)
  end
  def flatten #maybe name to_a ?
    #use Peter Taylor's fix to avoid quadratic flatten times
    Garray.new(flatten_append([]))
  end
  def flatten_append(prefix)
    @val.inject(prefix){|s,i|case i
      when Numeric then s<<i
      when Garray then i.flatten_append(s)
      when Gstring then s.concat(i.val)
      when Gblock then s.concat(i.val)
       end
    }
  end
  def ginspect
    bs = []
    @val.each{|i| bs << 32; bs.concat(i.ginspect.val) }
    bs[0] = 91
    bs << 93
    Gstring.new(bs)
  end
  def go
    Stack<<self
  end
  def class_id; GArrayId; end
  def gscoerce(b)
    c = b.class_id
    if c == 0
      b.gscoerce(self).reverse
    elsif c == 2
      [Gstring.new(self),b]
    else
      [(self*Gstring.new(' ')).to_s.compile,b]
    end
  end

  def leftparen
    gwarn "left paren on empty list" if @val.empty?
    Stack.concat [factory(@val[1..-1]),@val[0]]
  end
  def rightparen
    gwarn "right paren on empty list" if @val.empty?
    Stack.concat [factory(@val[0..-2]),@val[-1]]
  end
  def *(b)
    if b.class_id == GIntId
      factory(@val*b)
    else
      return b*self if self.class == Gstring && b.class == Garray
      return Garray.new(@val.map{|n|Gstring.new([n])})*b if self.class == Gstring
      return b.factory([]) if @val.size<1
      r=@val.first.dup
      r,x=r.gscoerce(b) if r.class != b.class #for size 1
      @val[1..-1].each{|i|r=r.concat(b); r=r.concat(i)}
      r
    end
  end
  def /(b)
    if b.class_id==GIntId
      r=[]
      a = b < 0 ? @val.reverse : @val
      i = -b = b.abs
      r << factory(a[i,b]) while (i+=b)<a.size
      Garray.new(r)
    else
      split(b,false)
    end
  end
  def %(b)
    if b.class_id==GIntId
      factory((0..(@val.size-1)/b.abs).inject([]){|s,i|
        s<<@val[b < 0 ? i*b - 1 : i*b]
      })
    else
      split(b,true)
    end
  end
  def split(b,no_empty)
    r=[]
    i=b.factory([])
    j=0
    while j<@val.size
      if @val[j,b.val.size]==b.val
        r<<i unless no_empty && i.val.empty?
        i=b.factory([])
        j+=b.val.size
      else
        i.val<<@val[j]
        j+=1
      end
    end
    r<<i unless no_empty && i.val.empty?
    Garray.new(r)
  end
  def falsey; @val.empty?; end
  def question(b); @val.index(b)||-1; end
  def equalop(b); b.class_id==GIntId ? @val[b] : (@val==b.val ? 1 : 0); end
  def ltop(b); b.class_id==GIntId ? factory(@val[0...b]) : (@val<b.val ? 1 : 0); end
  def gtop(b); b.class_id==GIntId ? factory(@val[[b,-@val.size].max..-1]) : (@val>b.val ? 1 : 0); end
  def sort; factory(@val.sort); end
  def zip
    r=[]
    @val.size.times{|x|
      @val[x].val.size.times{|y|
        (r[y]||=@val[0].factory([])).val<<@val[x].val[y]
      }
    }
    Garray.new(r)
  end
  def ~
    val
  end
  def comma
    @val.size
  end
end

class Gstring < Garray
  def initialize(a)
    @val=case a
      when NilClass then []
      when String then a.unpack('C*')
      when Array then a
      when Garray then a.flatten.val
    end
  end
  def factory(a)
    Gstring.new(a)
  end
  def to_gs
    self
  end
  def ginspect
    factory(to_s.inspect)
  end
  def to_s
    @val.pack('C*')
  end
  def class_id; GStringId; end
  def gscoerce(b)
    if b.class == Gblock
      [to_s.compile,b]
    else
      b.gscoerce(self).reverse
    end
  end
  def question(b)
    if b.class == Gstring
      to_s.index(b.to_s)||-1
    elsif b.class == Garray
      b.question(self)
    else
      @val.index(b)||-1
    end
  end
  def ~
    to_s.compile.go
    nil
  end
end

class LazyInput
  def method_missing(meth, *args, &block)
    @input ||= (
      STDERR.puts "waiting for input to proceed, Ctrl-D for proceed"
      Gstring.new(STDIN.read))
    @input.send(meth, *args, &block)
  end
  undef class
  def ginspect
    Gstring.new("LazyInput")
  end
  def to_gs
    Gstring.new("")
  end
end

class RubyCode
  def initialize(source,safe)
    @source = source
    @safe = safe # unsafe if this code could execute a golfscript block
  end
  def unsafe_assignment; true; end
  attr_reader :source, :safe
  def go
    (@cc||=eval"lambda{#{replace_pops @source}}")[]
  end
end

def gpop(name)
  gwarn'pop on empty stack from %p'%name if Stack.empty?;i=LB.size;LB[i] -= 1 while i>0 && LB[i-=1] >= Stack.size;a=Stack.pop;
end
def gpop_inline(n,name)
  lhs=[*'a'..'d'][0,n]*","
  "(gwarn'pop on empty stack from #{name.inspect}';Stack.replace(([nil]*3+Stack.dup)[-#{n}..-1])) if Stack.size<#{n};i=LB.size;while i>0 && LB[i-=1] > (new_size = Stack.size-#{n});LB[i]=new_size;end;#{lhs}=Stack.pop #{n == 1 ? '' : n};"
end

def replace_pops(code)
  code
    .gsub(/POP1{(.*?)}/){ gpop_inline(1,$1) }
    .gsub(/POP2{(.*?)}/){ gpop_inline(2,$1) }
    .gsub(/POP3{(.*?)}/){ gpop_inline(3,$1) }
end

def exit_compiled(stmt_no)
   "return resume(#{stmt_no+1})"
end
def safety_check(stmt_no)
  "#{exit_compiled(stmt_no)} unless @compiled"
end
def wipe_all_compiled
  Blocks.each{|block|block.compiled = nil; block.call_count = 0}
end
NoEmptyCheck = "(gwarn'cannot assign empty stack';exit(1))if Stack.empty?"

Blocks=[]

class Gblock < Garray
  def initialize(impl,gs_source)
    @val=Gstring.new(gs_source).val
    @impl=impl
    @call_count = 0
    Blocks<<self
  end
  def unsafe_assignment; !(Stack.last.class_id==GBlockId); end
  attr_writer :call_count
  attr_accessor :compiled
  attr_reader :impl
  def go
    return @compiled.call if @compiled
    @call_count += 1
    return resume(0) if @call_count < 55
    # generate ruby code by inlining what each token will do
    # this code could become invalid because you can assign anything to anything anytime
    # so be ready to exit out and resume with safe code
    optimized=@impl.map.with_index{|stmt,stmt_no|
      type,var_name=*stmt
      case type
      when :block
        "Stack<<"+var_name
      when :assign
        "#{NoEmptyCheck};if #{var_name}.unsafe_assignment; #{var_name}=Stack.last;wipe_all_compiled;#{exit_compiled(stmt_no)};else;#{var_name}=Stack.last;end"
      when :var
        case (val=eval(var_name))
        when NilClass
          ""
        when RubyCode
          "#{val.source};#{val.safe ? '' : safety_check(stmt_no)}"
        when Gblock
          "#{var_name}.go;#{safety_check(stmt_no)}"
        else
          "Stack<<"+var_name
        end
      else;error;end
    }*"\n"

    optimized.gsub!(/Stack<<([^;\n]*)[;\n]+POP3/, 'c=\1;POP2')
    optimized.gsub!(/Stack<<([^;\n]*)[;\n]+POP2/, 'b=\1;POP1')
    optimized.gsub!(/Stack<<([^;\n]*)[;\n]+POP1{.*?}/, 'a=\1;')
    @compiled = eval("lambda{#{replace_pops optimized}}")
    @compiled.call
  end
  def resume(line)
    return @cc.call if line==0 && @cc
    source = @impl[line..-1].map{|type,var_name|
      case type
      when :block
        "Stack<<"+var_name
      when :assign
        "#{NoEmptyCheck};wipe_all_compiled if #{var_name}.unsafe_assignment;#{var_name}=Stack.last"
      when :var
        "#{var_name}.go"
      else;error;end
    }*";"
    if line==0
      @cc=eval"lambda{#{source}}"
      @cc.call
    else
      eval source
    end
  end
  def factory(b)
    Gstring.new(b).to_s.compile
  end
  def class_id; GBlockId; end
  def to_gs
    Gstring.new(([123]+@val)<<125)
  end
  def ginspect
    to_gs
  end
  def gscoerce(b)
    b.gscoerce(self).reverse
  end

  def addop(b)
    if b.class != self.class
      a,b=gscoerce(b)
      a.addop b
    else
      (@val+[32]+b.val).pack('C*').compile
    end
  end
  def *(b)
    if b.class_id==GIntId
      b.to_i.times{go}
    else
      gpush01 b.val.first
      (b.val[1..-1]||[]).each{|i|Stack<<i; go}
    end
    nil
  end
  def /(b)
    if b.class==Garray||b.class==Gstring
      b.val.each{|i|Stack << i; go}
      nil
    else #unfold
      r=[]
      loop{
        gwarn "unfold on empty stack generates nils" if Stack.empty?
        Stack<<Stack.last
        go
        break if gpop("unfold condition").falsey;
        gwarn "unfold on empty stack generates nils" if Stack.empty?
        r<<Stack.last
        b.go
      }
      gpop("unfold result")
      Garray.new(r)
    end
  end
  def %(b)
    r=[]
    b.val.each{|i|
      lb=Stack.size
      Stack<<i; go
      r.concat(Stack.slice!(lb..Stack.size))
    }
    r=Garray.new(r)
    b.class == Gstring ? Gstring.new(r) : r
  end
  def ~
    go
    nil
  end
  def sort
    a=gpop("sort")
    a.factory(a.val.stable_sort_by{|i|Stack<<i; go; gpop("sort by iteration")})
  end
  def select(a)
    a.factory(a.val.select{|i|Stack<<i;go; !gpop("select iteration").falsey})
  end
  def question(b)
    b.val.find{|i|Stack<<i; go; gpop("? iteration").notop==0}
  end
  def comma
    self.select(gpop("comma"))
  end
end

class NilClass
  def go
  end
  def unsafe_assignment; true; end
end
class Array
  def ^(rhs)
    self-rhs|rhs-self
  end
  include Comparable
  def stable_sort_by
    sort_by.with_index{|e,i|[yield(e),i]}
  end
end

$var_lookup={}
def var(name,val=nil)
  eval"#{s="$_#{$var_lookup[name]||=$var_lookup.size}"}||=val"
  s
end

$nprocs=0

IdentifierRx = /[a-zA-Z_][a-zA-Z0-9_]*/mn
StringRx = /'(?:\\.|[^'])*'?|"(?:\\.|[^"])*"?/mn
NumRx = /-?[0-9]+/mn
CommentRx = /#[^\n\r]*/mn
TokenRx = /#{IdentifierRx}|#{StringRx}|#{NumRx}|#{CommentRx}|./mn

def lex(s)
  s.scan(TokenRx)
end

class String
  def compile(interactive_mode = false)
    tokens=lex(self)
    block,ind=compile_helper(tokens,0,0,interactive_mode)
    block
  end
  def compile_helper(tokens,ind,depth,interactive_mode)
    statements=[]
    last=nil
    begin_no=ind
    loop {
      if ind >= tokens.size
        break if begin_no==0
        if interactive_mode
          while ind >= tokens.size
            s=Readline.readline("  "*depth + "> ", true)
            exit(0) if !s
            tokens.concat lex(s)
          end
        else
          pwarn "unmatched {", tokens, begin_no
          break
        end
      end
      t=tokens[-1+ind+=1]

      last=t
      statements.append case t
        when "{" then
          block,ind = *compile_helper(tokens,ind,depth+1,interactive_mode)
          [:block,var("{#{$nprocs+=1}",block)]
        when "}" then
          pwarn "unmatched }", tokens, ind if begin_no == 0
          break
        when ":"
          pwarn "setting the space token (probably accidental)", tokens, ind if tokens[ind]==" "
          pwarn "expecting identifier, found EOF", tokens, ind if ind>=tokens.size
          pwarn "cannot really set "+tokens[ind], tokens, ind if "{}:".chars.include? tokens[ind]
          [:assign,var(tokens[-1+ind+=1])]
        when /^["']/ then [:var,var(t,Gstring.new(NoInterpolationOption ? eval(t.gsub('#', '# ')).gsub('# ','#') : eval(t)))]
        when /^-?[0-9]/ then [:var,var(t,t.to_i)]
        else; [:var,var(t)]
      end
    }
    source=tokens[begin_no...ind-(last=="}"?1:0)]*""
    [Gblock.new(statements,source), ind]
  end
end

def gpush a
  Stack.push(*a) if a
end
def gpush01 a
  Stack.push(a) if a
end

def cc(n,name,impl,safe=true)
  var name,RubyCode.new(n == 0 ? impl : "POP#{n}{#{name}}" + impl,safe)
end
def order(name,impl,safe=true)
  cc 2,name,'a,b=b,a if a.class_id<b.class_id;'+impl,safe
end

Warned = {}

def gwarn(msg)
  return if Warned[msg]
  Warned[msg] = true
  warn("Warning: "+msg)
end

def pwarn(msg,tokens,ind)
  return if Warned[msg]
  Warned[msg] = true
  before=tokens[0...ind-1]*""
  line_no = before.count("\n")+1
  char_no = (before.lines.last||[]).size+1
  gwarn "#{line_no}:#{char_no}:(#{tokens[ind-1]}) #{msg}"
end

Unsafe = false
cc 0,'[','LB<<Stack.size'
cc 0,']','Stack<<Garray.new(Stack.slice!((LB.pop||0)..-1))'
cc 1,'~','gpush ~a',Unsafe
cc 1,'`','Stack<<a.ginspect'
cc 1,';',''
cc 1,'.','Stack<<a;Stack<<a'
cc 2,'\\','Stack<<b;Stack<<a'
cc 3,'@','Stack<<b<<c;Stack<<a'
cc 2,'+','Stack<<a.addop(b)'
cc 2,'-','Stack<<a.subop(b)'
cc 2,'|','Stack<<a.uniop(b)'
cc 2,'&','Stack<<a.intop(b)'
cc 2,'^','Stack<<a.difop(b)'
order '*','gpush01 a*b',Unsafe
order '/','gpush01 a/b',Unsafe
order '%','Stack<<a%b',Unsafe
order '=','gpush01 a.equalop(b)',Unsafe
order '<','Stack<<a.ltop(b)'
order '>','Stack<<a.gtop(b)'
cc 1,'!','Stack<<a.notop'
order '?','gpush01 a.question(b)',Unsafe
cc 1,'$','gpush01 (a.class_id==GIntId ? Stack[~a.to_i] : a.sort)',Unsafe
cc 1,',','Stack<<a.comma',Unsafe
cc 1,')','a.rightparen'
cc 1,'(','a.leftparen'

cc 1,'rand','Stack<<rand([1,a].max)'
cc 1,'abs','Stack<<a.abs'
cc 1,'print','print a.to_gs'
cc 2,'if',"#{var'!'}.go;(gpop('if')==0?a:b).go",Unsafe
cc 1,'do',"loop{a.go; #{var'!'}.go; break if gpop('do')!=0}",Unsafe
cc 2,'while',"loop{a.go; #{var'!'}.go; break if gpop('while')!=0; b.go}",Unsafe
cc 2,'until',"loop{a.go; #{var'!'}.go; break if gpop('unitl')==0; b.go}",Unsafe
cc 1,'zip','Stack<<a.zip'
cc 2,'base','Stack<<b.base(a)'

cc 0,'V','puts "Golfscript 1.0 Beta, Ruby #{RUBY_VERSION}"'
cc 0,'Q','puts \'http://golfscript.com/golfscript/quickref.html
       name   args meanings
          ~      1 bitwise not, dump, eval
          `      1 inspect
          !      1 logical not
          @      3 rotate
          #        comment
          $ 1 or 2 stack ith, sort(by)
          + coerce add, concat
          - coerce subtract, set diff
          *  order mult, block execute times, array repeat, join, fold
          /  order div, split, split in groups of size, unfold, each
          %  order mod, map, every ith element, clean split
          | coerce bitwise/setwise or
          & coerce bitwise/setwise and
          ^ coerce bitwise/setwise xor
        { }        blocks
          \\\'        raw string
          "        escaped string
        [ ]        Array creation
          \\      2 swap 2
          :     1* assignment
          ;      1 pop
          <  order less than, elements less than index
          >  order greater than, elements greater than or equal to index
          =  order equal to, element at index
          , 1 or 2 [*0...n], size, select
          .      1 dup
          ?  order pow, index, find
          (      1 deincrement, uncons
          )      1 increment, right uncons
 and or xor      2
      print      1
          p      1
          n      0
       puts      1
       rand      1
         do      1
while until      2
         if      3
        abs      1
        zip      1
       base      2
          V      0 Print Golfscript/Ruby version
          Q      0 Print quick ref\''

Stack = []

'"\n":n;
{print n print}:puts;
{`puts}:p;
{1$if}:and;
{1$\if}:or;
{\!!{!}*}:xor;
'.compile.go

if filenames.empty?
  puts "Golfscript Interactive Mode"
  require "readline"
  while (code=Readline.readline("> ", true))
    begin
      code.compile(true).go
      gpush Garray.new(Stack)
      'p'.compile.go
    rescue
      puts "#{$!.class}: #{$!.message}"
    end
  end
else
  code=File.read(filenames[0])
  if gs_args.empty?
    Stack << (STDIN.isatty ? LazyInput.new : Gstring.new(STDIN.read))
  else
    Stack << Garray.new(gs_args.map{|arg| Gstring.new(arg)})
  end

  code.compile.go
  gpush Garray.new(Stack)
  'puts'.compile.go if !QuineOption
end
