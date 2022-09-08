#!/usr/bin/env ruby

# (c) Copyright 2008 Darren Smith.
# MIT License.

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

class Gtype
  def initialize_copy(other); @val = other.val.dup; end
  attr_reader :val
  def addop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.addop(b)) : factory(@val + rhs.val); end
  def subop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.subop(b)) : factory(@val - rhs.val); end
  def uniop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.uniop(b)) : factory(@val | rhs.val); end
  def intop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.intop(b)) : factory(@val & rhs.val); end
  def difop(rhs); rhs.class != self.class ? (a,b=gscoerce(rhs); a.difop(b)) : factory(@val ^ rhs.val); end
  def ==(rhs); Gtype === rhs && @val==rhs.val; end
  def eql?(rhs); Gtype === rhs && @val==rhs.val; end
  def hash; @val.hash; end
  def <=>(rhs); @val<=>rhs.val; end
  def notop; self.falsey ? 1 : 0; end
end

class Numeric
  def class_id; 0; end
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
  if ARGV.include? "-r"
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
    if Garray===a
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
  def class_id; 1; end
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
    if Numeric === b
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
    if Numeric===b
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
    if Numeric === b
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
  def equalop(b); Numeric === b ? @val[b] : (@val==b.val ? 1 : 0); end
  def ltop(b); Numeric === b ? factory(@val[0...b]) : (@val<b.val ? 1 : 0); end
  def gtop(b); Numeric === b ? factory(@val[[b,-@val.size].max..-1]) : (@val>b.val ? 1 : 0); end
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
  def class_id; 2; end
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

class RubyCode
  def initialize(source,safe)
    @source = source
    @safe = safe # unsafe if this code could execute a golfscript block
  end
  def unsafe_assignment; true; end
  attr_reader :source, :safe
  def go
    (@cc||=eval"lambda{#{@source}}")[]
  end
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
  def unsafe_assignment; !(Gblock===Stack.last); end
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

    # convert a push followed by pop2 to just a pop1
    optimized.gsub!(/Stack<<([^;\n]*)[;\n]+#{Regexp.escape Gpop2_inline}/){
      "b="+$1+";"+Gpop1_inline
    }
    # remove a push followed by a pop
    optimized.gsub!(/Stack<<([^;\n]*)[;\n]+#{Regexp.escape Gpop1_inline}/){
      "a="+$1+";"
    }
    @compiled = eval("lambda{#{optimized}}")
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
  def class_id; 3; end
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
    if Numeric===b
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
        Stack<<Stack.last
        go
        break if gpop.falsey;
        r<<Stack.last
        b.go
      }
      gpop
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
    a=gpop
    a.factory(a.val.sort_by{|i|Stack<<i; go; gpop})
  end
  def select(a)
    a.factory(a.val.select{|i|Stack<<i;go; !gpop.falsey})
  end
  def question(b)
    b.val.find{|i|Stack<<i; go; gpop.notop==0}
  end
  def comma
    self.select(gpop)
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
            print "  "*depth + "> "
            s=gets
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
        when /^["']/ then [:var,var(t,Gstring.new(eval(t)))]
        when /^-?[0-9]/ then [:var,var(t,t.to_i)]
        else; [:var,var(t)]
      end
    }
    source=tokens[begin_no...ind-(last=="}"?1:0)]*""
    [Gblock.new(statements,source), ind]
  end
end
Gpop1_inline = "gwarn'pop on empty stack' if Stack.empty?;i=LB.size;LB[i] -= 1 while i>0 && LB[i-=1] >= Stack.size;a=Stack.pop;"
eval "def gpop;#{Gpop1_inline};end"
gpopn_inline = "(gwarn'pop on empty stack';Stack.replace(([nil]*3+Stack.dup)[-%d..-1])) if Stack.size<%d;i=LB.size;while i>0 && LB[i-=1] > (new_size = Stack.size-%d);LB[i]=new_size;end;%s=Stack.pop(%d);"
Gpop2_inline = gpopn_inline % [2,2,2,"a,b",2]
Gpop3_inline = gpopn_inline % [3,3,3,"a,b,c",3]
def gpush a
  Stack.push(*a) if a
end
def gpush01 a
  Stack.push(a) if a
end

class String
  def ccs
    RubyCode.new(self,true)
  end
  def ccu
    RubyCode.new(self,false)
  end
  def cc1s
    (Gpop1_inline+self).ccs
  end
  def cc1u
    (Gpop1_inline+self).ccu
  end
  def cc2s
    (Gpop2_inline+self).ccs
  end
  def cc2u
    (Gpop2_inline+self).ccu
  end
  def cc3s
    (Gpop3_inline+self).ccs
  end
  def cc3u
    (Gpop3_inline+self).ccu
  end
  def orders
    (Gpop2_inline+'a,b=b,a if a.class_id<b.class_id;'+self).ccs
  end
  def orderu
    (Gpop2_inline+'a,b=b,a if a.class_id<b.class_id;'+self).ccu
  end
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

var'[','LB<<Stack.size'.ccs
var']','Stack<<Garray.new(Stack.slice!((LB.pop||0)..-1))'.ccs
var'~','gpush ~a'.cc1u
var'`','Stack<<a.ginspect'.cc1s
var';',''.cc1s
var'.','Stack<<a;Stack<<a'.cc1s
var'\\','Stack<<b;Stack<<a'.cc2s
var'@','Stack<<b<<c;Stack<<a'.cc3s
var'+','Stack<<a.addop(b)'.cc2s
var'-','Stack<<a.subop(b)'.cc2s
var'|','Stack<<a.uniop(b)'.cc2s
var'&','Stack<<a.intop(b)'.cc2s
var'^','Stack<<a.difop(b)'.cc2s
var'*','gpush01 a*b'.orderu
var'/','gpush01 a/b'.orderu
var'%','Stack<<a%b'.orderu
var'=','gpush01 a.equalop(b)'.orderu
var'<','Stack<<a.ltop(b)'.orders
var'>','Stack<<a.gtop(b)'.orders
var'!','Stack<<a.notop'.cc1s
var'?','gpush01 a.question(b)'.orderu
var'$','gpush01 (Numeric===a ? Stack[~a.to_i] : a.sort)'.cc1u
var',','Stack<<a.comma'.cc1u
var')','a.rightparen'.cc1s
var'(','a.leftparen'.cc1s

var'rand','Stack<<rand([1,a].max)'.cc1s
var'abs','Stack<<a.abs'.cc1s
var'print','print a.to_gs'.cc1s
var'if',"#{var'!'}.go;(gpop==0?a:b).go".cc2u
var'do',"loop{a.go; #{var'!'}.go; break if gpop!=0}".cc1u
var'while',"loop{a.go; #{var'!'}.go; break if gpop!=0; b.go}".cc2u
var'until',"loop{a.go; #{var'!'}.go; break if gpop==0; b.go}".cc2u
var'zip','Stack<<a.zip'.cc1s
var'base','Stack<<b.base(a)'.cc2s

Stack = []

'"\n":n;
{print n print}:puts;
{`puts}:p;
{1$if}:and;
{1$\if}:or;
{\!!{!}*}:xor;
'.compile.go

if ARGV.empty?
  puts "Golfscript Interactive Mode"
  while (print "> "; code=gets)
    code.compile(true).go
    gpush Garray.new(Stack)
    'p'.compile.go
  end
else
  code=gets(nil)||''
  input=$stdin.isatty ? '' : $stdin.read
  Stack << Gstring.new(input)

  code.compile.go
  gpush Garray.new(Stack)
  'puts'.compile.go
end
