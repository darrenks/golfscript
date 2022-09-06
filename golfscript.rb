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
  def go
    Stack<<self
  end
  def val
    @val
  end

  '+-|&^'.each_byte{|i|
    eval'def %c(rhs)
      if rhs.class != self.class
        a,b=coerce(rhs)
        a %c b
      else
        factory(@val %c rhs.val)
      end
    end'%([i]*3)
  }
  def ==(rhs)
    @val==rhs.val
  end
  def eql?(rhs)
    @val==rhs.val
  end
  def hash
    @val.hash
  end
  def <=>(rhs)
    @val<=>rhs.val
  end
end

class Gint < Gtype
  def initialize(i)
    @val = case i
      when true then 1
      when false then 0
      else;i
    end
  end
  def factory(a)
    Gint.new(a)
  end
  def to_gs
    Gstring.new(@val.to_s)
  end
  def to_int #for pack
    @val
  end
  def ginspect
    to_gs
  end
  def class_id; 0; end
  def coerce(b)
    [if b.class == Garray
      Garray.new([self])
    elsif b.class == Gstring
      to_gs
    else #Gblock
      to_gs.to_s.compile
    end,b]
  end

  def ~
    Gint.new(~@val)
  end
  def notop
    Gint.new(@val == 0)
  end
  '*/%<>'.each_byte{|i|
    eval'def %c(rhs)
      Gint.new(@val %c rhs.val)
    end'%[i,i]
  }
  def equalop(rhs)
    Gint.new(@val == rhs.val)
  end
  if ARGV.include? "-r"
    def question(b)
      Gint.new((b.val<0 && @val.equal?(1) ? 1r : @val) ** b.val)
    end
  else
    def question(b)
      Gint.new(@val**(b.val<0 ? b.val.to_f : b.val))
    end
  end
  def base(a)
    if Garray===a
      r=0
      a.val.each{|i|
        r*=@val
        r+=i.val
      }
      Gint.new(r)
    else
      i=a.val.abs
      r=[]
      while i!=0
        r.unshift Gint.new(i%@val)
        i/=@val
      end
      Garray.new(r)
    end
  end
  def leftparen
    Stack<<Gint.new(@val-1)
  end
  def rightparen
    Stack<<Gint.new(@val+1)
  end
  def comma
    Garray.new([*0...@val].map{|i|Gint.new(i)})
  end
end

class Garray < Gtype
  def initialize(a)
    @val = a || []
  end
  def concat(rhs)
    if rhs.class != self.class
      a,b=coerce(rhs)
      a+b
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
      when Gint then s<<i
      when Garray then i.flatten_append(s)
      when Gstring then s.concat(i.val)
      when Gblock then s.concat(i.val)
       end
    }
  end
  def ginspect
    Gstring.new('[')+Garray.new(@val.map{|i|i.ginspect})*Gstring.new(' ')+Gstring.new(']')
  end
  def go
    Stack<<self
  end
  def class_id; 1; end
  def coerce(b)
    if b.class == Gint
      b.coerce(self).reverse
    elsif b.class == Gstring
      [Gstring.new(self),b]
    else
      [(self*Gstring.new(' ')).to_s.compile,b]
    end
  end

  def leftparen
    Stack.concat [factory(@val[1..-1]),@val[0]]
  end
  def rightparen
    Stack.concat [factory(@val[0..-2]),@val[-1]]
  end
  def *(b)
    if b.class == Gint
      factory(@val*b.val)
    else
      return b*self if self.class == Gstring && b.class == Garray
      return Garray.new(@val.map{|n|Gstring.new([n])})*b if self.class == Gstring
      return b.factory([]) if @val.size<1
      r=@val.first.dup
      r,x=r.coerce(b) if r.class != b.class #for size 1
      @val[1..-1].each{|i|r=r.concat(b); r=r.concat(i)}
      r
    end
  end
  def /(b)
    if b.class == Gint
      r=[]
      a = b.val < 0 ? @val.reverse : @val
      i = -b = b.val.abs
      r << factory(a[i,b]) while (i+=b)<a.size
      Garray.new(r)
    else
      r=[]
      i=b.factory([])
      j=0
      while j<@val.size
        if @val[j,b.val.size]==b.val
          r<<i
          i=b.factory([])
          j+=b.val.size
        else
          i.val<<@val[j]
          j+=1
        end
      end
      r<<i
      Garray.new(r)
    end
  end
  def %(b)
    if b.class == Gint
      b=b.val
      factory((0..(@val.size-1)/b.abs).inject([]){|s,i|
        s<<@val[b < 0 ? i*b - 1 : i*b]
      })
    else
      self/b-Garray.new([Garray.new([])])
    end
  end
  def notop
    Gint.new(@val.empty?)
  end
  def question(b)
    Gint.new(@val.index(b)||-1)
  end
  def equalop(b)
    if b.class == Gint
      @val[b.val]
    else
      Gint.new(@val==b.val)
    end
  end
  def <(b)
    if b.class == Gint
      factory(@val[0...b.val])
    else
      Gint.new(@val<b.val)
    end
  end
  def >(b)
    if b.class == Gint
      factory(@val[[b.val,-@val.size].max..-1])
    else
      Gint.new(@val>b.val)
    end
  end
  def sort
    factory(@val.sort)
  end
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
    Gint.new(@val.size)
  end
end

class Gstring < Garray
  def initialize(a)
    @val=case a
      when NilClass then []
      when String then a.unpack('C*').map{|i|Gint.new(i)}
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
  def coerce(b)
    if b.class == Gblock
      [to_s.compile,b]
    else
      b.coerce(self).reverse
    end
  end
  def question(b)
    if b.class == Gstring
      Gint.new(to_s.index(b.to_s)||-1)
    elsif b.class == Garray
      b.question(self)
    else
      Gint.new(@val.index(b)||-1)
    end
  end
  def ~
    to_s.compile.go
    nil
  end
end

class Gblock < Garray
  def initialize(_a,_b=nil)
    @val=Gstring.new(_b).val
    @a=_a
  end
  def go
    (@native||=eval("lambda{#{@a}}")).call
  end
  def factory(b)
    Gstring.new(b).to_s.compile
  end
  def class_id; 3; end
  def to_gs
    Gstring.new("{"+Gstring.new(@val).to_s+"}")
  end
  def ginspect
    to_gs
  end
  def coerce(b)
    b.coerce(self).reverse
  end

  def +(b)
    if b.class != self.class
      a,b=coerce(b)
      a+b
    else
      Gstring.new(@val+Gstring.new(" ").val+b.val).to_s.compile
    end
  end
  def *(b)
    if b.class == Gint
      b.val.times{go}
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
        break if gpop.notop.val!=0;
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
    a.factory(a.val.select{|i|Stack<<i;go; gpop.notop.val==0})
  end
  def question(b)
    b.val.find{|i|Stack<<i; go; gpop.notop.val==0}
  end
  def comma
    self.select(gpop)
  end
end

class NilClass
  def go
  end
end
class Array
  def ^(rhs)
    self-rhs|rhs-self
  end
  include Comparable
end

code=gets(nil)||''
$_=$stdin.isatty ? '' : $stdin.read
Stack = [Gstring.new($_)]
$var_lookup={}

def var(name,val=nil)
  eval"#{s="$_#{$var_lookup[name]||=$var_lookup.size}"}||=val"
  s
end

$nprocs=0

class String
  def compile(tokens=scan(/[a-zA-Z_][a-zA-Z0-9_]*|'(?:\\.|[^'])*'?|"(?:\\.|[^"])*"?|-?[0-9]+|#[^\n\r]*|./mn))
     orig=tokens.dup
    native=""
    while t=tokens.slice!(0)
      native<<case t
        when "{" then "Stack<<"+var("{#{$nprocs+=1}",compile(tokens))
        when "}" then break
        when ":" then var(tokens.slice!(0))+"=Stack.last"
        when /^["']/ then var(t,Gstring.new(eval(t)))+".go"
        when /^-?[0-9]+/ then var(t,Gint.new(t.to_i))+".go"
        else; var(t)+".go"
        end+"\n"
    end
    source=orig[0,orig.size-tokens.size-(t=="}"?1:0)]*""
    Gblock.new(native,source)
  end
end
# todo wouldn't hurt much timewise to add stack size checking for nice error msg
Gpop_inline = "i=LB.size;LB[i] -= 1 while i>0 && LB[i-=1] >= Stack.size;a=Stack.pop;"
eval "def gpop;#{Gpop_inline};end"
gpopn_inline = "i=LB.size;while i>0 && LB[i-=1] > (new_size = Stack.size-%d);LB[i]=new_size;end;%s=Stack.pop(%d);"
Gpop2_inline = gpopn_inline % [2,"a,b",2]
Gpop3_inline = gpopn_inline % [3,"a,b,c",3]
def gpush a
  Stack.push(*a) if a
end
def gpush01 a
  Stack.push(a) if a
end

class String
  def cc
    Gblock.new(self)
  end
  def cc1
    (Gpop_inline+self).cc
  end
  def cc2
    (Gpop2_inline+self).cc
  end
  def cc3
    (Gpop3_inline+self).cc
  end
  def order
    (Gpop2_inline+'a,b=b,a if a.class_id<b.class_id;'+self).cc
  end
end

var'[','LB<<Stack.size'.cc
var']','Stack<<Garray.new(Stack.slice!((LB.pop||0)..-1))'.cc
var'~','gpush ~a'.cc1
var'`','Stack<<a.ginspect'.cc1
var';',''.cc1
var'.','Stack<<a<<a'.cc1
var'\\','Stack<<b<<a'.cc2
var'@','Stack<<b<<c<<a'.cc3
var'+','Stack<<a+b'.cc2
var'-','Stack<<a-b'.cc2
var'|','Stack<<(a|b)'.cc2
var'&','Stack<<(a&b)'.cc2
var'^','Stack<<(a^b)'.cc2
var'*','gpush01 a*b'.order
var'/','gpush01 a/b'.order
var'%','Stack<<a%b'.order
var'=','gpush01 a.equalop(b)'.order
var'<','Stack<<(a<b)'.order
var'>','Stack<<(a>b)'.order
var'!','Stack<<a.notop'.cc1
var'?','gpush01 a.question(b)'.order
var'$','gpush01 (a.class==Gint ? Stack[~a.val] : a.sort)'.cc1
var',','Stack<<a.comma'.cc1
var')','a.rightparen'.cc1
var'(','a.leftparen'.cc1

var'rand','Stack<<Gint.new(rand([1,a.val].max))'.cc1
var'abs','Stack<<Gint.new(a.val.abs)'.cc1
var'print','print a.to_gs'.cc1
var'if',"#{var'!'}.go;(gpop.val==0?a:b).go".cc2
var'do',"loop{a.go; #{var'!'}.go; break if gpop.val!=0}".cc1
var'while',"loop{a.go; #{var'!'}.go; break if gpop.val!=0; b.go}".cc2
var'until',"loop{a.go; #{var'!'}.go; break if gpop.val==0; b.go}".cc2
var'zip','Stack<<a.zip'.cc1
var'base','Stack<<b.base(a)'.cc2

'"\n":n;
{print n print}:puts;
{`puts}:p;
{1$if}:and;
{1$\if}:or;
{\!!{!}*}:xor;
'.compile.go
code.compile.go
gpush Garray.new(Stack)
'puts'.compile.go
