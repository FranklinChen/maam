# Introduction

Traditional practice in program analysis via abstract interpretation is to fix
a language (as a concrete semantics) and an abstraction (as an abstraction map,
concretization map or Galois connection) before constructing a static analyzer
that it sound with respect to both the abstraction and the concrete semantics.
Thus, each pairing of abstraction and semantics requires a one-off manual
derivation of the abstract semantics and a construction of a proof of
soundness.

Work has focused on endowing abstractions with knobs, levers, and dials to tune
precision and compute efficiently.  These parameters come with overloaded
meanings such as object, context, path, and heap sensitivities, or some
combination thereof.  These efforts develop families of analyses _for a
specific language_ and prove the framework sound.

But this framework approach suffers from many of the same drawbacks as the
one-off analyzers.  They are language-specific, preventing reuse of concepts
across languages and require similar re-implementations and soundness proofs.
This process is still manual, tedious, difficult and error-prone. And, changes
to the structure of the parameter-space require a completely new proof of
soundness.  And, it prevents fruitful insights and results developed in one
paradigm from being applied to others, e.g., functional to object-oriented and
_vice versa_.

We propose an automated alternative approach to structuring and implementing
program analysis.  Inspired by \citeauthor*{dvanhorn:Liang1995Monad}'s
\emph{Monad transformers for modular interpreters}
\citeyearpar{dvanhorn:Liang1995Monad}, we propose to start with concrete
interpreters in a specific monadic style. Changing the monad will change the
interpreter from a concrete interpreter into an abstract interpreter. As we
show, classical program abstractions can be embodied as language-independent
monads.  Moreover, these abstractions can be written as monad _transformers_,
thereby allowing their composition to achieve new forms of analysis.  We show
that these monad transformers obey the properties of \emph{Galois connections}
\cite{dvanhorn:Cousot1979Systematic} and introduce the concept of a
\emph{Galois transformer}, a monad transformer which transports Galois
connections.

Most significantly, Galois transformers can be proved sound once and used
everywhere.  Abstract interpreters, which take the form of monad transformer
stacks coupled together with a monadic interpreter, inherit the soundness
properties of each element in the stack.  This approach enables reuse of
abstractions across languages and lays the foundation for a modular metatheory
of program analysis.

Using Galois transformers, we enable arbitrary composition of analysis
parameters. For example, our implementation--called `maam`--supports
command-line flags for garbage collection, k-CFA, and path  and
flow sensitivity.
``````````````````````````````````````````````````
./maam --gc --CFA=0 --flow-sen prog.lam
``````````````````````````````````````````````````
These flags are implemented independently of one another and are applied to a
single parameterized monadic interpreter. Furthermore, using Galois
transformers allows us to prove each combination correct in one fell swoop.

\paragraph{Setup}
We describe a simple language and a garbage-collecting allocating semantics as
the starting point of analysis design (Section \ref{semantics}). We then
briefly discuss three types of flow  and path sensitivities and their
corresponding variations in analysis precision (Section
\ref{flow-properties-in-analysis}).

\paragraph{Monadic Abstract Interpreters}
We develop an abstract interpreter for our example language as a monadic
function with various parameters (Section \ref{analysis-parameters}), one of
which is a monadic effect interface combining state and nondeterminism effects
(Section \ref{the-analysis-monad}). Interpreters written in this style can be
reasoned about using laws that must hold for each of these interfaces.
Likewise, instantiations for these parameters can be reasoned about in
isolation from their instantiation. When instantiated, our generic interpreter
is capable of recovering the concrete semantics and a family of abstract
interpreters, with variations in abstract domain, call-site sensitivity, and
flow  and path sensitivity (Section \ref{recovering-analyses}).

\paragraph{Isolating Path  and Flow Sensitivity}
We give specific monads for instantiating the interpreter from Section
\ref{the-interpreter} which give rise to path-sensitive and flow-insensitive
analyses (Section \ref{varying-path-and-flow-sensitivity}). This leads to an
isolated understanding of path  and flow sensitivity as mere variations in the
monad used for execution. Furthermore, these monads are language independent,
allowing one to reuse the same path  and flow sensitivity machinery for any
language of interest.

\paragraph{Galois Transformers}
To ease the construction of monads for building abstract interpreters and their
proofs of correctness, we develop a framework of Galois transformers (Section
\ref{a-compositional-monadic-framework}). Galois transformers are an extension
of monad transformers which transport Galois connections in addition to monadic
operations. Our Galois transformer framework allows us to reason about the
correctness of an abstract interpreter piecewise for each transformer in a
stack. Galois transformers are language independent and they can be proven
correct one and for all in isolation from a particular semantics.

\paragraph{Implementation}
We implement our technique in Haskell and briefly discuss how the parameters
from Section \ref{analysis-parameters} translate into code (Section
\ref{implementation-1}). Our implementation is publicly available on
Hackage\footnote{http://hackage.haskell.org/package/maam}, Haskell's package
manager.


\paragraph{Contributions}
We make the following contributions:

- A framework for building abstract interpreters using monad transformers.
- A framework for constructing Galois connections using _Galois
  transformers_, an extension of monad transformers which also transport Galois
  connections.
- A new monad transformer for nondeterminism which we show is also a Galois
  transformer.
- An isolated understanding of flow  and path sensitivity for static analysis
  as a property of the interpreter monad.

# Semantics

To demonstrate our framework we design an abstract interpreter for `λIF`, a
simple applied lambda calculus shown in Figure`~\ref{SS}`{.raw}. `λIF` extends
traditional lambda calculus with integers, addition, subtraction and
conditionals. We use the operator `[@]` as explicit abstract syntax for
function application.

`\begin{figure}`{.raw}
\vspace{-1em}
`````align````````````````````````````````````````
 i ∈  ℤ       x ∈ Var
 a ∈  Atom    ::= i | x | [λ](x).e
 ⊕ ∈  IOp     ::= [+] | [-]
 ⊙ ∈  Op      ::= ⊕ | [@]
 e ∈  Exp     ::= a | e ⊙ e | [if0](e){e}{e}
<>
 τ ∈  Time    := ℤ
 l ∈  Addr    := Var × Time
 ρ ∈  Env     := Var ⇀ Addr
 σ ∈  Store   := Addr ⇀ Val
 c ∈  Clo     ::= ⟨[λ](x).e,ρ⟩ 
 v ∈  Val     ::= i | c
κl ∈  KAddr   := Time
κσ ∈  KStore  := KAddr ⇀ Frame × KAddr
fr ∈  Frame   ::= ⟨□ ⊙ e⟩ | ⟨v ⊙ □⟩ | ⟨[if0](□){e}{e}⟩
 ς ∈  Σ       ::= Exp × Env × Store × KAddr × KStore
``````````````````````````````````````````````````
`\caption{`{.raw} `λIF` Syntax and Concrete State Space `}`{.raw}
\label{SS} 
\vspace{-1em}
`\end{figure}`{.raw}

Before designing an abstract interpreter we first specify a formal semantics
for `λIF`. Our semantics makes allocation explicit using two separate stores
for values (`Store`) and the control stack (`KStore`). We will recover these
semantics from our generic abstract interpreter in Section
\ref{recovering-analyses}.

We give semantics to atomic expressions and primitive operators denotationally
through `A⟦_⟧` and `δ⟦_⟧` respectively as shown in
Figure`~\ref{ConcreteDenotationFunctions}`{.raw}; and to compound expressions
relationally as shown in Figure`~\ref{ConcreteStepRelation}`{.raw}.

`\begin{figure}`{.raw}
\vspace{-1em}
`````indent```````````````````````````````````````
A⟦_⟧ ∈ Atom → (Env × Store ⇀ Val)
A⟦i⟧(ρ,σ) := i
A⟦x⟧(ρ,σ) := σ(ρ(x))
A⟦[λ](x).e⟧(ρ,σ) := ⟨[λ](x).e,ρ⟩ 
<>
δ⟦_⟧ ∈ IOp → (ℤ × ℤ → ℤ)
δ⟦[+]⟧(i₁,i₂) := i₁ + i₂
δ⟦[-]⟧(i₁,i₂) := i₁ - i₂
``````````````````````````````````````````````````
\caption{Concrete Denotation Functions}
\label{ConcreteDenotationFunctions} 
\vspace{-1em}
`\end{figure}`{.raw}

`\begin{figure}`{.raw}
\vspace{-1em}
`````indent```````````````````````````````````````
_[~~>]_ ∈ 𝒫(Σ × Σ)
⟨e₁ ⊙ e₂,ρ,σ,κl,κσ,τ⟩ ~~> ⟨e₁,ρ,σ,τ,κσ',τ+1⟩
  where κσ' := κσ[τ ↦ (⟨□ ⊙ e₂⟩,κl)]
⟨a,ρ,σ,κl,κσ,τ⟩ ~~> ⟨e,ρ,σ,τ,κσ',τ+1⟩
  where 
    (⟨□ ⊙ e⟩,κl') := κσ(κl)
    κσ' := κσ[τ ↦ (⟨A⟦a⟧(ρ,σ) ⊙ □⟩,κl')]
⟨a,ρ,σ,κl,κσ,τ⟩ ~~> ⟨e,ρ'',σ',κl',κσ,τ+1⟩
  where 
    (⟨⟨[λ](x).e,ρ'⟩ [@] □⟩,κl') := κσ(κl)
    ρ'' := ρ'[x ↦ (x,τ)]
    σ' := σ[(x,τ) ↦ A⟦a⟧(ρ,σ)]
⟨i₂,ρ,σ,κl,κσ,τ⟩ ~~> ⟨i,ρ,σ,κl',κσ,τ+1⟩
  where 
    (⟨i₁ ⊕ □⟩,κl') := κσ(κl)
    i := δ⟦⊕⟧(i₁,i₂)
⟨i,ρ,σ,κl,κσ,τ⟩ ~~> ⟨e,ρ,σ,κl',κσ,τ+1⟩
  where 
    (⟨[if0](□){e₁}{e₂}⟩,κl') := κσ(κl)
    e := e₁ when i = 0
    e := e₂ when i ≠ 0
``````````````````````````````````````````````````
\caption{Concrete Step Relation}
\label{ConcreteStepRelation} 
\vspace{-1em}
`\end{figure}`{.raw}

Our abstract interpreter will support abstract garbage
collection`~\cite{dvanhorn:Might:2006:GammaCFA}`{.raw}, the concrete analogue
of which is just standard garbage collection. We include abstract garbage
collection for two reasons. First, it is one of the few techniques that results
in both performance _and_ precision improvements for abstract interpreters.
Second, later we will systematically recover both concrete and abstract garbage
collectors through a single monadic garbage collector.

Garbage collection is defined using a reachability function `R` which computes
the transitively reachable address from `(ρ,e)` in `σ`:
`````indent```````````````````````````````````````
R ∈ Store × Env × Exp → 𝒫(Addr)
R(σ,ρ,e) := μ(X). 
  X ∪ R₀(ρ,e) ∪ {l' | l' ∈ R-Val(σ(l)) ; l ∈ X}
``````````````````````````````````````````````````
We write `μ(X). f(X)` as the least-fixed-point of a function `f`. This
definition uses two helper functions: `R₀` for computing the initial reachable
set and `R-Val` for computing addresses reachable from values.
`````indent```````````````````````````````````````
R₀ ∈ Env × Exp → 𝒫(Addr)
R₀(ρ,e) := {ρ(x) | x ∈ FV(e)}
<>
R-Val ∈ Val → 𝒫(Addr)
R-Val(i) := {}
R-Val(⟨[λ](x).e,ρ⟩) := {ρ(y) | y ∈ FV([λ](x).e)}
``````````````````````````````````````````````````
We omit the definition of `FV`, which is the standard recursive definition for
computing free variables of an expression.

Analogously, `KR` is the set of transitively reachable continuation addresses
in `κσ`:
`````indent```````````````````````````````````````
KR ∈ KStore × KAddr → 𝒫(KAddr)
KR(κσ,κl₀) := μ(X). X ∪ {κl₀} ∪ {π₂(κσ(κl)) | κl ∈ X}
``````````````````````````````````````````````````

Our final semantics is given via the step relation `_[~~>⸢gc⸣]_` which
nondeterministically either takes a semantic step or performs garbage
collection.
`````indent```````````````````````````````````````
_[~~>⸢gc⸣]_ ∈ 𝒫(Σ × Σ)
ς ~~>⸢gc⸣ ς' 
  where ς ~~> ς'
⟨e,ρ,σ,κl,κσ,τ⟩ ~~>⸢gc⸣ ⟨e,ρ,σ',κl,κσ',τ⟩
  where 
    σ' := {l ↦ σ(l) | l ∈ R(σ,ρ,e)}
    κσ' := {κl ↦ κσ(κl) | κl ∈ KR(κσ,κl)}
``````````````````````````````````````````````````

An execution of the semantics is the least-fixed-point of a collecting
semantics:
`````indent```````````````````````````````````````
μ(X).X ∪ {ς₀} ∪ { ς' | ς ~~>⸢gc⸣ ς' ; ς ∈ X }
``````````````````````````````````````````````````
where `ς₀` is the injection of the initial program `e₀`:
`````indent```````````````````````````````````````
ς₀ := ⟨e₀,⊥,⊥,0,⊥,1⟩
``````````````````````````````````````````````````
The analyses we present in this paper will be proven correct by establishing a
Galois connection with this concrete collecting semantics.

# Flow Properties in Analysis

The term "flow" is heavily overloaded in static analysis. In this paper we
identify three types of analysis flow:

1. Path sensitivity
2. Flow sensitivity
3. Flow insensitivity


Our framework exposes the essence of analysis flow, and therefore allows for
many other choices in addition to these three. However, these properties occur
frequently in the literature and have well-understood definitions, so we
restrict our discussion them.

Consider a combination of if-statements in our example language `λIF` (extended
with let-bindings) where an analysis cannot determine the value of `N`:
`````raw``````````````````````````````````````````
\begin{alignat*}{3}
``````````````````````````````````````````````````
`````rawmacro`````````````````````````````````````
& 1: [let] x :=           && ␣␣[in]                 \\
& ␣␣2: [if0](N){          && ␣␣5: [let] y :=        \\
& ␣␣␣␣3: [if0](N){1}{2}   && ␣␣␣␣6: [if0](N){5}{6}  \\
& ␣␣} [else] {            && ␣␣[in]                 \\
& ␣␣␣␣4: [if0](N){3}{4}   && ␣␣7: [exit](x, y)      \\
& ␣␣}                     && \\
``````````````````````````````````````````````````
`````raw``````````````````````````````````````````
\end{alignat*}
``````````````````````````````````````````````````

\paragraph{Path-Sensitive}
A path-sensitive analysis will track both data and control flow precisely. At
program points 3 and 4 the analysis considers separate worlds:
`````align````````````````````````````````````````
3: {N=0} \quad 4: {N≠0}
``````````````````````````````````````````````````
At program point 6 the analysis continues in two separate, precise worlds:
`````align````````````````````````````````````````
6: {N=0,, x=1} {N≠0,, x=4}
``````````````````````````````````````````````````
At program point 7 the analysis correctly corrolates the values of `x` and
`y`:
`````align````````````````````````````````````````
7: {N=0,, x=1,, y=5} {N≠0,, x=4,, y=6}
``````````````````````````````````````````````````

\paragraph{Flow-Sensitive}
A flow-sensitive analysis will collect a _single_ set of facts about each
variable _at each program point_. At program points 3 and 4, the analysis
considers separate worlds:
`````align````````````````````````````````````````
3: {N=0} \quad 4: {N≠0}
``````````````````````````````````````````````````
Each nested if-statement then evaluates only one side of the branch. At program
point 6 the analysis is only allowed one set of facts, so it must merge the
possible values that `x` and `N` could take:
`````align````````````````````````````````````````
6: {N∈ℤ,, x∈{1,4}}
``````````````````````````````````````````````````
The analysis must then explore both branches at program point 6 resulting in no
corrolation between values for `x` and `y`:
`````align````````````````````````````````````````
7: {N∈ℤ,, x∈{1,4},, y∈{5,6}}
``````````````````````````````````````````````````

\paragraph{Flow-Insensitive}
A flow-insensitive analysis will collect a _single_ set of facts about each
variable which must hold true _for the entire program_. Because the value of
`N` is unknown at _some_ point in the program, the value of `x` must consider
both branches of the nested if-statement. This results in the global set of
facts giving four values to `x`.
`````align````````````````````````````````````````
{N∈ℤ,, x∈{1,2,3,4},, y∈{5,6}}
``````````````````````````````````````````````````

In our framework we capture each flow property as a purely orthogonal parameter
to the abstract interpreter. Flow properties will compose seamlessly with
choices of call-site sensitivity, object sensitivity, abstract garbage
collection, mcfa a la \citet{dvanhorn:Might2010Resolving}, shape analysis,
abstract domain, etc. Most importantly, we empower the analysis designer to
_compartmentalize_ the flow sensitivity of each component in the abstract state
space. Constructing an analysis which is flow-sensitive in the data store and
path-sensitive in the control store is just as easy as constructing a single
flow property across the board, and one can alternate between them for free.

# Analysis Parameters

Before writing an abstract interpreter we first design its parameters. The
interpreter will be designed such that variations in these parameters will
recover both concrete and a family of abstract interpreters. To do this we
extend the ideas developed in \citet{davdar:van-horn:2010:aam} with a new
parameter for path  and flow sensitivity. When finished, we will recover both
the concrete semantics and a family of abstractions through instantiations of
these parameters.

There will be three parameters to our abstract interpreter, one of which is
novel in this work:

1. The monad, novel in this work, is the execution engine of the interpreter
   and captures path and flow sensitivity.
2. The abstract domain, which for this language is merely an abstraction for
   integers.
3. Abstract Time, capturing call-site and object sensitivities.

We place each of these parameters behind an abstract interface and leave their
implementations opaque for the generic monadic interpreter. We give each of
these parameters reasoning principles as we introduce them. These principles
allow us to reason about the correctness of the generic interpreter independent
of a particular instantiation. The goal is to factor as much of the
proof-effort into what we can say about the generic interpreter. An
instantiation of the interpreter need only justify that each parameter meets
its local interface.

## The Analysis Monad

The monad for the interpreter captures the _effects_ of interpretation. There
are two effects we wish to model in the interpreter: state and nondeterminism.
The state effect will mediate how the interpreter interacts with state cells in
the state space: `Env`, `Store`, `KAddr` and `KStore`. The nondeterminism
effect will mediate branching in the execution of the interpreter. Our result
is that path and flow sensitivities can be recovered by altering how these
effects interact in the monad.

We briefly review monad, state and nondeterminism operators and their laws.

\paragraph{Monadic Sequencing}
A type operator `M` is a monad if it supports `bind`, a sequencing operator,
and its unit `return`.
`````align```````````````````````````````````````` 
M        : Type → Type
bind     : ∀ α β, M(α) → (α → M(β)) → M(β)
return   : ∀ α, α → M(α)
``````````````````````````````````````````````````

We use monad laws (left and right units, and associativity) to reason about our
interpreter in the absence of a particular implementation of `bind` and
`return`. As is traditional with monadic programming, we use semicolon notation
as syntactic sugar for `bind`. For example: `a ← m ; k(a)` is just sugar for
`bind(m)(k)`. We replace semicolons with line breaks headed by a `do` command
for multiline monadic definitions.

\paragraph{State Effect}
A type operator `M` supports the monadic state effect for a type `s` if it
supports `get` and `put` actions over `s`.
`````align```````````````````````````````````````` 
M        : Type → Type
s        : Type
get      : M(s)
put      : s → M(1)
``````````````````````````````````````````````````
We use the state monad laws to reason about state effects, and we refer the
reader to \citet{dvanhorn:Liang1995Monad} for the definitions.

\paragraph{Nondeterminism Effect}
A type operator `M` support the monadic nondeterminism effect if it supports an
alternation operator `⟨+⟩` and its unit `mzero`.
`````align```````````````````````````````````````` 
M        : Type → Type
_[⟨+⟩]_  : ∀ α, M(α) × M(α) → M(α)
mzero    : ∀ α, M(α)
``````````````````````````````````````````````````
Nondeterminism laws state that `M(α)` must have a join-semilattice structure,
that `mzero` be a zero for `bind`, and that `bind` distributes through `⟨+⟩`.

\paragraph{Monad Examples}
The state monad `Stateₛ(α)` is defined as `s → (α × s)` and supports monadic
sequencing (`bind` and `return`) and state effects (`get` and `put`). The
nondeterminism monad `Nondet(α)` is defined as `𝒫(α)` and supports monadic
sequencing (`bind` and `return`) and nondeterminism effects (`_[⟨+⟩]_` and
`mzero`).

The combined interface of monadic sequencing, state and nondeterminism captures
the abstract essence of definitions which use explicit state-passing and set
comprehensions. Our interpreter will be defined up to this effect interface and
avoid referencing an explicit configuration `ς` or explicit collections of
results. This level of indirection will they be exploited: different monads
will meet the same effect interface, but yield different analysis properties.

## The Abstract Domain

`````align````````````````````````````````````````
    int-I  : ℤ → Val
int-if0-E  : Val → 𝒫(Bool)
    clo-I  : Clo → Val
    clo-E  : Val → 𝒫(Clo)
``````````````````````````````````````````````````

The abstract domain is encapsulated by the `Val` type in the semantics. To
parameterize over the abstract domain we make `Val` opaque, but require that it
support various operations.

`Val` must be a join-semilattice with `⊥` and `⊔` respecting the usual
laws. We require `Val` to be a join-semilattice so it can be merged in the
`Store` to preserve soundness. 
`````align````````````````````````````````````````
⊥      : Val
_[⊔]_  : Val × Val → Val
``````````````````````````````````````````````````

`Val` must also support conversions to and from concrete values. These
conversions take the form of introduction and elimination rules. Introduction
rules inject concrete values into abstract values. Elimination rules project
abstract values into a _finite_ set of concrete observations. For example, we
do not require that abstract values support elimination to integers, only the
finite observation of comparing with zero.
`````align````````````````````````````````````````
    int-I  : ℤ → Val
int-if0-E  : Val → 𝒫(Bool)
    clo-I  : Clo → Val
    clo-E  : Val → 𝒫(Clo)
``````````````````````````````````````````````````

The laws for the introduction and elmination rules are designed to induce a
Galois connection between `𝒫(ℤ)` and `Val`:
`````indent```````````````````````````````````````
{true}  ⊑ int-if0-E(int-I(i))     if i = 0
{false} ⊑ int-if0-E(int-I(i))     if i ≠ 0
⨆⸤b ∈ int-if0-E(v), i ∈ θ(b)⸥ int-I(i) ⊑ v
  where 
    θ(true)  = {0}
    θ(false) = {i | i ∈ ℤ ; i ≠ 0}
``````````````````````````````````````````````````
Closures must follow similar laws, inducing a Galois connection between
`𝒫(Clo)` and `Val`:
`````indent```````````````````````````````````````
{c} ⊑ clo-E(cloI(c))
⨆⸤c ∈ clo-E(v)⸥ clo-I(c) ⊑ v
``````````````````````````````````````````````````
Finally, `δ` must be sound and complete w.r.t. the abstract semantics:
`````indent```````````````````````````````````````
int-I(i₁ + i₂) ⊑ δ⟦[+]⟧(int-I(i₁),int-I(i₂))
int-I(i₁ - i₂) ⊑ δ⟦[-]⟧(int-I(i₁),int-I(i₂))
⨆⸤b₁ ∈ int-if0-E(v₁), b₂ ∈ int-if0-E(v₂), i ∈ θ(b₁,b₂)⸥ int-I(i) ⊑ δ⟦⊙⟧(v₁,v₂)
  where
    θ(true,true) = {0}
    θ(true,false) = {i | i ∈ ℤ ; i ≠ 0}
    θ(false,true) = {i | i ∈ ℤ ; i ≠ 0}
    θ(false,false) = ℤ
``````````````````````````````````````````````````

Supporting additional primitive types like booleans, lists, or arbitrary
inductive datatypes is analogous. Introduction functions inject the type into
`Val`. Elimination functions project a finite set of discrete observations.
Introduction, elimination and `δ` operators must be sound and complete
following a Galois connection discipline.

## Abstract Time 

The interface for abstract time is familiar from
`\citet{davdar:van-horn:2010:aam}`{.raw}(AAM) which introduces abstract time as
a single parameter from variations in call-site sensitivity, and
`\citet{dvanhorn:Smaragdakis2011Pick}`{.raw} which instantiates the parameter
to achieve both call-site and object sensitivity.
`````align````````````````````````````````````````
Time  : Type
tick  : Exp × KAddr × Time → Time
``````````````````````````````````````````````````

Remarkably, we need not state laws for `tick`. Our interpreter will always
merge values which reside at the same address to achieve soundness. Therefore,
any supplied implementations of `tick` is valid from a soundness perspective.
Different choices in `tick` merely yield different tradoffs in precision and
performance of the abstract semantics.

# The Interpreter

We now present a generic monadic interpreter for `λIF` parameterized over `M`,
`Val` and `Time`. First we implement `A⟦_⟧`, a _monadic_ denotation for atomic
expressions.
`````indent```````````````````````````````````````
A⟦_⟧ ∈ Atom → M(Val)
A⟦i⟧ := return(int-I(i))
A⟦x⟧ := do
  ρ ← get-Env
  σ ← get-Store
  if x ∈ ρ
    then return(σ(ρ(x)))
    else return(⊥)
A⟦[λ](x).e⟧ := do
  ρ ← get-Env
  return(clo-I(⟨[λ](x).e,ρ⟩))
``````````````````````````````````````````````````
`get-Env` and `get-Store` are primitive operations for monadic state. `clo-I`
comes from the abstract domain interface. 

Next we implement `step`, a _monadic_ small-step function for compound
expressions, shown in Figure \ref{InterpreterStep}. `step` uses helper
functions `push` and `pop` for manipulating stack frames, `↑ₚ` for lifting
values from `𝒫` into `M`, and a monadic version of `tick` called `tickM`, each
of which are shown in Figure \ref{InterpreterHelpers}. The interpreter looks
deterministic, however the nondeterminism is abstracted away behind `↑ₚ` and
monadic bind `x ← e₁ ; e₂`.

`\begin{figure}`{.raw}
\vspace{-1em}
`````indent```````````````````````````````````````
step : Exp → M(Exp)
step(e₁ ⊙ e₂) := do
  tickM(e₁ ⊙ e₂)
  push(⟨□ ⊙ e₂⟩)
  return(e₁)
step(a) := do
  tickM(a)
  fr ← pop
  v ← A⟦a⟧
  case fr of
    ⟨□ ⊙ e⟩ → do
      push(⟨v ⊙ □⟩)
      return(e)
    ⟨v' [@] □⟩ → do
      ⟨[λ](x).e,ρ'⟩ ← ↑ₚ(clo-E(v'))
      τ ← get-Time
      σ ← get-Store
      put-Env(ρ'[x ↦ (x,τ)])
      put-Store(σ ⊔ [(x,τ) ↦ {v}])
      return(e)
    ⟨v' ⊕ □⟩ → do
      return(δ⟦⊕⟧(v',v))
    ⟨[if0](□){e₁}{e₂}⟩ → do
      b ← ↑ₚ(int-if0-E(v))
      if(b) then return(e₁) else return(e₂)
``````````````````````````````````````````````````
\caption{Monadic step function and garbage collection}
\label{InterpreterStep} 
\vspace{-1em}
`\end{figure}`{.raw}

`\begin{figure}`{.raw}
\vspace{-1em}
`````indent```````````````````````````````````````
↑ₚ : ∀ α, 𝒫(α) → M(α)
↑ₚ({a₁ .. aₙ}) := return(a₁) ⟨+⟩ .. ⟨+⟩ return(aₙ)
<>
push : Frame → M(1)
push(fr) := do
  κl ← get-KAddr
  κσ ← get-KStore
  κl' ← get-Time
  put-KStore(κσ ⊔ [κl' ↦ {fr∷κl}])
  put-KAddr(κl')
<>
pop : M(Frame)
pop := do
  κl ← get-KAddr
  κσ ← get-KStore
  fr∷κl' ← ↑ₚ(κσ(κl))
  put-KAddr(κl')
  return(fr)
<>
tickM : Exp → M(1)
tickM(e) = do
  τ ← get-Time
  κl ← get-KAddr
  put-Time(tick(e,κl,τ))
``````````````````````````````````````````````````
\caption{Monadic step function and garbage collection}
\label{InterpreterHelpers} 
\vspace{-1em}
`\end{figure}`{.raw}

We also implement abstract garbage collection in a general away using the
monadic effect interface:
`````indent```````````````````````````````````````
gc : Exp → M(1)
gc(e) := do
  ρ ← get-Env
  σ ← get-Store
  κσ ← get-KStore
  put-Store({l ↦ σ(l) | l ∈ R(σ,ρ,e))
  put-KStore({κl ↦ κσ(κl) | κl ∈ KR(κσ,κl)})
``````````````````````````````````````````````````
where `R` and `KR` are as defined in Section`~\ref{semantics}`{.raw}. 

In generalizing the semantics to account for nondeterminism, updates to both
the value and continuation store must merge values rather than performing a
strong update. This is because we place no restriction on the semantics for
`Time` and therefore must preserve soundness in the presence of reused
addresses.

To support the `⊔` operator for our stores (in observation of soundness), we
modify our definitions of `Store` and `KStore`.
`````indent```````````````````````````````````````
σ  ∈ Store  : Addr → Val
κσ ∈ KStore : KAddr → 𝒫(Frame × KAddr)
``````````````````````````````````````````````````

We have already established a join-semilattice structure for `Val` in the
abstract domain interface. Developing a custom join-semilattice for
continuations is possible and is the key component of recent developments in
pushdown abstraction. For this presentation we use `𝒫(Frame × KAddr)` as an
abstraction for continuations for simplicity.

To execute the interpreter we must introduce one more parameter. In the
concrete semantics, execution takes the form of a least-fixed-point computation
over the collecting semantics. This in general requires a join-semilattice
structure for some `Σ` and a transition function `Σ → Σ`.

For the monadic interpreter we require that monadic actions `Exp → M(Exp)` form
a Galois connection with a transition system `Σ → Σ`. This Galois connection
serves two purposes. First, it allows us to implement the analysis by
converting our interpreter to the transition system `Σ → Σ` through `γ`.
Second, this Galois connection serves to _transport other Galois connections_
as part of our correctness framework. For example, given concrete and abstract
versions of `Val`, we carry `CVal α⇄γ AVal` through the Galois connection to
establish `CΣ α⇄γ AΣ`.

A collecting-semantics execution of our interpreter is defined as the
least-fixed-point of `step` transported through the Galois connection `(Σ → Σ)
α⇄γ (Exp → M(Exp))`.
`````indent```````````````````````````````````````
μ(X). X ⊔ ς₀ ⊔ γ(step)(X)
``````````````````````````````````````````````````
where `ς₀` is the injection of the initial program `e₀` into `Σ` and `γ` has
type `(Exp → M(Exp)) → (Σ → Σ)`.

# Recovering Analyses

To recover concrete and abstract interpreters we need only instantiate our
generic monadic interpreter with concrete and abstract components. The concrete
interpreter will recover the concrete semantics from Section \ref{semantics},
and through that correspondance, the soundness proof for the abstract semantics
will be recovered largely for free.

## Recovering a Concrete Interpreter

For the concrete value space we instantiate `Val` to `CVal`:
`````indent```````````````````````````````````````
v ∈ CVal := 𝒫(CClo + ℤ)
``````````````````````````````````````````````````

The concrete value space `CVal` has straightforward introduction and
elimination rules:
`````indent```````````````````````````````````````
int-I : ℤ → CVal
int-I(i) := {i}
int-if0-E : CVal → 𝒫(Bool)
int-if0-E(v) := { true | 0 ∈ v } ∪ { false | ∃ i ∈ v ∧ i ≠ 0 }
``````````````````````````````````````````````````
and a straightforward concrete `δ`:
`````indent```````````````````````````````````````
δ⟦_⟧(_,_) : IOp → CVal × CVal → CVal
δ⟦[+]⟧(v₁,v₂) := { i₁ + i₂ | i₁ ∈ v₁ ; i₂ ∈ v₂ }
δ⟦[-]⟧(v₁,v₂) := { i₁ - i₂ | i₁ ∈ v₁ ; i₂ ∈ v₂ }
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`CVal` satisfies the abstract domain laws shown in Section
\ref{the-abstract-domain}.
`\end{proposition}`{.raw}

Concrete time `CTime` captures program contours as a product of `Exp` and
`CKAddr`:
`````indent```````````````````````````````````````
τ ∈ CTime := (Exp × KAddr)⸢*⸣
``````````````````````````````````````````````````
and `tick` is just a cons operator:
`````indent```````````````````````````````````````
tick : Exp × CKAddr × CTime → CTime
tick (e,κl,τ) := (e,κl)∷τ
``````````````````````````````````````````````````

For the concrete monad we instantiate `M` to a path-sensitive `CM` which
contains a powerset of concrete state space components.
`````indent```````````````````````````````````````
ψ ∈ Ψ := CEnv × CStore × CKAddr × CKStore × CTime
m ∈ CM(α) := Ψ → 𝒫(α × Ψ)
``````````````````````````````````````````````````

Monadic operators `bind` and `return` encapsulate both state-passing and
set-flattening:
`````indent```````````````````````````````````````
bind : ∀ α, CM(α) → (α → CM(β)) → CM(β)
bind(m)(f)(ψ) := 
  {(y,ψ'') | (y,ψ'') ∈ f(a)(ψ') ; (a,ψ') ∈ m(ψ)}
return : ∀ α, α → CM(α)
return(a)(ψ) := {(a,ψ)}
``````````````````````````````````````````````````

State effects merely return singleton sets:
`````indent```````````````````````````````````````
get-Env : CM(CEnv)
get-Env(⟨ρ,σ,κ,τ⟩) := {(ρ,⟨ρ,σ,κ,τ⟩)}
put-Env : CEnv → 𝒫(1)
put-Env(ρ')(⟨ρ,σ,κ,τ⟩) := {(1,⟨ρ',σ,κ,τ⟩)}
``````````````````````````````````````````````````

Nondeterminism effects are implemented with set union:
`````indent```````````````````````````````````````
mzero : ∀ α, CM(α)
mzero(ψ) := {}
_[⟨+⟩]_ : ∀ α, CM(α) × CM(α) → CM(α)
(m₁ ⟨+⟩ m₂)(ψ) := m₁(ψ) ∪ m₂(ψ)
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`CM` satisfies monad, state, and nondeterminism laws shown in Section
\ref{the-analysis-monad}.
`\end{proposition}`{.raw}

Finally, we must establish a Galois connection between `Exp → CM(Exp)` and `CΣ
→ CΣ` for some choice of `CΣ`. For the path-sensitive monad `CM` instantiated
with `CVal` and `CTime`, `CΣ` is defined:
`````indent```````````````````````````````````````
CΣ := 𝒫(Exp × Ψ)
``````````````````````````````````````````````````

The Galois connection between `CM` and `CΣ` is straightforward:
`````indent```````````````````````````````````````
γ : (Exp → CM(Exp)) → (CΣ → CΣ)
γ(f)(eψ⸢*⸣) := {(e,ψ') | (e,ψ') ∈ f(e)(ψ) ; (e,ψ) ∈ eψ⸢*⸣}
α : (CΣ → CΣ) → (Exp → CM(Exp))
α(f)(e)(ψ) := f({(e,ψ)})
``````````````````````````````````````````````````

The injection `ς₀` for a program `e₀` is:
`````indent```````````````````````````````````````
ς₀ := {⟨e,⊥,⊥,∙,⊥,∙⟩}
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`γ` and `α` form an isomorphism, and therefore a Galois connection.
`\end{proposition}`{.raw}

## Recovering an Abstract Interpreter

We pick a simple abstraction for integers, `{[-],0,[+]}`, although our
technique scales seamlessly to other domains.
`````indent```````````````````````````````````````
AVal := 𝒫(AClo + {[-],0,[+]})
``````````````````````````````````````````````````

Introduction and elimination for `AVal` are defined:
`````indent```````````````````````````````````````
int-I : ℤ → AVal
int-I(i) := {[-]} if i < 0
int-I(i) := {0}   if i = 0
int-I(i) := {[+]} if i > 0
int-if0-E : AVal → 𝒫(Bool)
int-if0-E(v) := { true | 0 ∈ v } ∪ { false | [-] ∈ v ∨ [+] ∈ v }
``````````````````````````````````````````````````
Introduction and elimination for `AClo` is identical to the concrete domain.

The abstract `δ` operator is defined:
`````indent```````````````````````````````````````
δ : IOp → AVal × AVal → AVal 
δ⟦[+]⟧(v₁,v₂) := 
    { i         | 0 ∈ v₁ ∧ i ∈ v₂ }
  ∪ { i         | i ∈ v₁ ∧ 0 ∈ v₂ }
  ∪ { [+]       | [+] ∈ v₁ ∧ [+] ∈ v₂ } 
  ∪ { [-]       | [-] ∈ v₁ ∧ [-] ∈ v₂ } 
  ∪ { [-],0,[+] | [+] ∈ v₁ ∧ [-] ∈ v₂ }
  ∪ { [-],0,[+] | [-] ∈ v₁ ∧ [+] ∈ v₂ }
``````````````````````````````````````````````````
The definition for `δ⟦[-]⟧(v₁,v₂)` is analogous.

`\begin{proposition}`{.raw}
`AVal` satisfies the abstract domain laws shown in
Section`~\ref{the-abstract-domain}`{.raw}.
`\end{proposition}`{.raw}

`\begin{proposition}`{.raw}
`CVal α⇄γ AVal` and their operations `int-I`, `int-if0-E` and `δ` are ordered
`⊑` respectively through the Galois connection.
`\end{proposition}`{.raw}

Next we abstract `Time` to `ATime` as the finite domain of k-truncated lists of
execution contexts:
`````indent```````````````````````````````````````
ATime := (Exp × AKAddr)⋆ₖ
``````````````````````````````````````````````````
The `tick` operator becomes cons followed by k-truncation, which restricts the
list to the first-k elements:
`````indent```````````````````````````````````````
tick : Exp × AKAddr × ATime → ATime
tick(e,κl,τ) = ⌊(e,κl)∷τ⌋ₖ
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`CTime α⇄γ ATime` and `tick` are ordered `⊑` through the Galois connection.
`\end{proposition}`{.raw}

The monad `AM` need not change in implementation from `CM`; they are identical
up the choice of `Ψ`.
`````indent```````````````````````````````````````
ψ ∈ Ψ := AEnv × AStore × AKAddr × AKStore × ATime
``````````````````````````````````````````````````

The resulting state space `AΣ` is finite, and its least-fixed-point iteration
will give a sound and computable analysis.

# Varying Path and Flow Sensitivity

We are able to recover a flow insensitive analysis through a new definition for
`M`: `AM⸢fi⸣`. To do this we pull `AStore` out of the powerset, exploiting its
join-semilattice structure:
`````indent```````````````````````````````````````
Ψ := AEnv × AKAddr × AKStore × ATime
AM⸢fi⸣(α) := Ψ × AStore → 𝒫(α × Ψ) × AStore
``````````````````````````````````````````````````

The monad operator `bind` performs the store merging needed to capture a
flow-insensitive analysis.
`````indent```````````````````````````````````````
bind : ∀ α β, AM⸢fi⸣(α) → (α → AM⸢fi⸣(β)) → AM⸢fi⸣(β)
bind(m)(f)(ψ,σ) := ({bs⸤11⸥ .. bs⸤1m₁⸥ .. bs⸤n1⸥ .. bs⸤nmₙ⸥},σ₁ ⊔ .. ⊔ σₙ)
  where
    ({(a₁,ψ₁) .. (aₙ,ψₙ)},σ') := m(ψ,σ)
    ({bψ⸤i1⸥ .. bψ⸤imᵢ⸥},σᵢ) := f(aᵢ)(ψᵢ,σ')
``````````````````````````````````````````````````
The unit for `bind` returns one nondeterminism branch and a single store:
`````indent```````````````````````````````````````
return : ∀ α, α → AM⸢fi⸣(α)
return(a)(ψ,σ) := ({a,ψ},σ)
``````````````````````````````````````````````````

State effects `get-Env` and `put-Env` are also straightforward, returning one
branch of nondeterminism:
`````indent```````````````````````````````````````
get-Env : AM⸢fi⸣(AEnv)
get-Env(⟨ρ,κ,τ⟩,σ) := ({(ρ,⟨ρ,κ,τ⟩)},σ)
put-Env : AEnv → AM⸢fi⸣(1)
put-Env(ρ')(⟨ρ,κ,τ⟩,σ) := ({(1,⟨ρ',κ,τ⟩)},σ)
``````````````````````````````````````````````````
State effects `get-Store` and `put-Store` are analogous to `get-Env` and
`put-Env`.

Nondeterminism operations will union the powerset and join the store pairwise:
`````indent```````````````````````````````````````
mzero : ∀ α, M(α)
mzero(ψ,σ) := ({}, ⊥)
_[⟨+⟩]_ : ∀ α, M(α) × M(α) → M α 
(m₁ ⟨+⟩ m₂)(ψ,σ) := (aψ*₁ ∪ aψ*₂,σ₁ ⊔ σ₂)
  where (aψ*ᵢ,σᵢ) := mᵢ(ψ,σ)
``````````````````````````````````````````````````

Finally, the Galois connection relating `AM⸢fi⸣` to a state space transition over
`AΣ⸢fi⸣` must also compute set unions and store joins pairwise:
`````indent```````````````````````````````````````
AΣ⸢fi⸣ := 𝒫(Exp × Ψ) × AStore
γ : (Exp → AM⸢fi⸣(Exp)) → (AΣ⸢fi⸣ → AΣ⸢fi⸣)
γ(f)(eψ*,σ) := ({eψ⸤11⸥ .. eψ⸤n1⸥ .. eψ⸤nm⸥}, σ₁ ⊔ .. ⊔ σₙ)
  where 
    {(e₁,ψ₁) .. (eₙ,ψₙ)} := eψ*
    ({eψ⸤i1⸥ .. eψ⸤im⸥},σᵢ) := f(eᵢ)(ψᵢ,σ)
α  : (AΣ⸢fi⸣ → AΣ⸢fi⸣) → (Exp → AM⸢fi⸣(Exp))
α(f)(e)(ψ,σ) := f({(e,ψ)},σ)
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`γ` and `α` form an isomorphism, and therefore a Galois connection.
`\end{proposition}`{.raw}

`\begin{proposition}`{.raw}
There exists Galois connections:
`````align````````````````````````````````````````
CM α₁⇄γ₁ AM α₂⇄γ₂ AM⸢fi⸣
``````````````````````````````````````````````````
`\end{proposition}`{.raw}
The first Galois connection `CM α₁⇄γ₁ AM` is justified piecewise by the Galois
connections between `CVal α⇄γ AVal` and `CTime α⇄γ ATime`. The second Galois
connection `AM α₂⇄γ₂ AM⸢fi⸣` is justified by calculation over their
definitions. We aim to recover this proof more easily through compositional
components in Section \ref{a-compositional-monadic-framework}.

`\begin{corollary}`{.raw}
`````align````````````````````````````````````````
CΣ α₁⇄γ₁ AΣ α₂⇄γ₂ AΣ⸢fi⸣
``````````````````````````````````````````````````
`\end{corollary}`{.raw}
This property is derived by transporting each Galois connection between monads
through their respective Galois connections to `Σ`.

`\begin{proposition}`{.raw}
The following orderings hold between the three induced transition relations:
`````align````````````````````````````````````````
α₁ ∘ Cγ(step) ∘ γ₁ ⊑ Aγ(step) ⊑ γ₂ ∘ Aγ⸢fi⸣(step) ∘ α₂
``````````````````````````````````````````````````
`\end{proposition}`{.raw}
This is a direct consequence of the monotonicity of step and the Galois
connections between monads.

We note that the implementation for our interpreter and abstract garbage
collector remain the same for each instantiation. They scale seamlessly to
path-sensitive and flow-insensitive variants when instantiated with the
appropriate monad. 

Recovering flow sensitivity is done through another analysis monad, which we
develop in Section \ref{a-compositional-monadic-framework} in a more general
setting.

# A Compositional Monadic Framework

In our development thus far, any modification to the interpreter requires
redesigning the monad `AM` and constructing new proofs relating `AM` to `CM`.
We want to avoid reconstructing complicated monads for our interpreters,
especially as languages and analyses grow and change. Even more, we want to
avoid reconstructing complicated _proofs_ that such changes will necessarily
require. Toward this goal we introduce a compositional framework for
constructing monads which are correct-by-construction--we extend the well-known
structure of monad transformer to that of _Galois transformer_.

There are two types of monadic effects used in our monadic interpreter: state
and nondeterminism. Each of these effects have corresponding monad
transformers. Transformers can be composed in either direction, and the two
possible directions of composition give rise naturally to path-sensitive and
flow-insenstive analyses. Furthermore, our definition of nondeterminism monad
transformer is novel in this work.

In the proceeding definitions, we must necessarily use `bind`, `return` and
other operations from the underlying monad. We notate these `bindₘ`, `returnₘ`,
`doₘ`, `←ₘ`,  etc. for clarity.

## State Monad Transformer

Briefly we review the state monad transformer, `Sₜ[s]`:
`````indent```````````````````````````````````````
Sₜ[_] : (Type → Type) → (Type → Type)
Sₜ[s](m)(α) := s → m(α × s)
``````````````````````````````````````````````````

The state monad transformer can transport monadic operations from `m` to
`Sₜ[s](m)`:
`````indent```````````````````````````````````````
bind : ∀ α β, Sₜ[s](m)(α) → (α → Sₜ[s](m)(β)) → Sₜ[s](m)(β)
bind(m)(f)(s) := doₘ
  (x,s') ←ₘ m(s)
  f(x)(s')
return : ∀ α, α → Sₜ[s](m)(α)
return(x)(s) := returnₘ(x,s)
``````````````````````````````````````````````````

The state monad transformer can also transport nondeterminism effects from `m`
to `Sₜ[s](m)`:
`````indent```````````````````````````````````````
mzero : ∀ α, Sₜ[s](m)(α)
mzero(s) := mzeroₘ 
_[⟨+⟩]_ : ∀ α, Sₜ[s](m)(α) × Sₜ[s](m)(α) → Sₜ[s](m)(α)
(m₁ ⟨+⟩ m₂)(s) := m₁(s) ⟨+⟩ₘ m₂(s) 
``````````````````````````````````````````````````

Finally, the state monad transformer exposes `get` and `put` operations
provided that `m` is a monad:
`````indent```````````````````````````````````````
get : Sₜ[s](m)(s)
get(s) := returnₘ(s,s)
put : s → Sₜ[s](m)(1)
put(s')(s) := returnₘ(1,s')
``````````````````````````````````````````````````

## Nondeterminism Monad Transformer

We have developed a new monad transformer for nondeterminism which composes
with state in both directions. Previous attempts to define a monad transformer
for nondeterminism have resulted in monad operations which do not respect
either monad laws or nondeterminism effect laws.

Our nondeterminism monad transformer is defined with the expected type,
embedding `𝒫` inside `m`:
`````indent```````````````````````````````````````
𝒫ₜ : (Type → Type) → (Type → Type)
𝒫ₜ(m)(α) := m(𝒫(α))
``````````````````````````````````````````````````

The nondeterminism monad transformer can transport monadic operations from `m`
to `𝒫ₜ` _provided that `m` is also a join-semilattice functor_:
`````indent```````````````````````````````````````
bind : ∀ α β, 𝒫ₜ(m)(α) → (α → 𝒫ₜ(m)(β)) → 𝒫ₜ(m)(β)
bind(m)(f) := doₘ
  {x₁ .. xₙ} ←ₘ m
  f(x₁) ⊔ₘ .. ⊔ₘ f(xₙ)
return : ∀ α, α → 𝒫ₜ(m)(α)
return(x) := returnₘ({x})
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`bind` and `return` satisfy the monad laws.
`\end{proposition}`{.raw}
The key lemma in this proof is the functorality of `m`, namely that:
`````align````````````````````````````````````````
returnₘ(x ⊔ y) = returnₘ(x) ⊔ returnₘ(y)
``````````````````````````````````````````````````

The nondeterminism monad transformer can transport state effects from `m` to
`𝒫ₜ`:
`````indent```````````````````````````````````````
get : 𝒫ₜ(m)(s)
get = mapₘ(λ(s).{s})(getₘ)
put : s → 𝒫ₜ(m)(1)
put(s) = mapₘ(λ(1).{1})(putₘ(s))
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`get` and `put` satisfy the state monad laws.
`\end{proposition}`{.raw}
The proof is by simple calculation.

Finally, our nondeterminism monad transformer exposes nondeterminism effects as
a straightforward application of the underlying monad's join-semilattice
functorality:
`````indent```````````````````````````````````````
mzero : ∀ α, 𝒫ₜ(m)(α)
mzero := ⊥ₘ
_[⟨+⟩]_ : ∀ α, 𝒫ₜ(m)(α) x 𝒫ₜ(m)(α) → 𝒫ₜ(m)(α)
m₁ ⟨+⟩ m₂ := m₁ ⊔ₘ m₂
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`mzero` and `⟨+⟩` satisfy the nondeterminism monad laws.
`\end{proposition}`{.raw}
The proof is trivial as a consequence of the underlying monad being a
join-semilattice functor.

Path sensitivity arises naturally when a state transformer sits on top of a
nondeterminism transformer. Flow insensitivity arises naturally when
nondeterminism sits on top of state.

## Mapping to State Spaces

Both our execution and correctness frameworks requires that monadic actions in
`m` map to state space transitions in `Σ`. We extend the earlier statement of
Galois connection to the transformer setting, mapping monad _transformer_
actions in `T` to state space _functor_ transitions in `Π`.
`````indent```````````````````````````````````````
T : (Type → Type) → (Type → Type)
Π : (Type → Type) → (Type → Type)
mstep : ∀ α β m, (α → T(m)(β)) α⇄γ (Π(Σₘ)(α) → Π(Σₘ)(β))
``````````````````````````````````````````````````
In the type of `mstep`, `m` is an arbitrary monad whose monadic actions map to
state space `Σₘ`. The monad transformer `T` must induce a state space
transformer `Π` for which `mstep` can be defined. We only show the `γ` sides of
the mappings in this section, which allow one to execute the analyses.

For the state monad transformer `Sₜ[s]` mstep is defined:
`````indent```````````````````````````````````````
mstep-γ : ∀ α β, 
  (α → Sₜ[s](m)(β)) → (Σₘ(α × s) → Σₘ(β × s))
mstep-γ(f) := mstepₘ-γ(λ(a,s). f(a)(s))
``````````````````````````````````````````````````

For the nondeterminism transformer `𝒫ₜ` mstep is defined:
`````indent```````````````````````````````````````
mstep-γ : ∀ α β, 
  (α → 𝒫ₜ(m)(β)) → (Σₘ(𝒫(α)) → Σₘ(𝒫(β)))
mstep-γ(f) := mstepₘ-γ(F)
  where F({x₁ .. xₙ}) = f(x₁) ⟨+⟩ .. ⟨+⟩ f(xₙ))
``````````````````````````````````````````````````
The Galois connections for `mstep` for both `Sₜ[s]` or `Pₜ` rely crucially on
`mstepₘ-γ` and `mstepₘ-α` being homomorphic, i.e. that:
`````align````````````````````````````````````````
α(id) ⊑ return
α(f ∘ g) ⊑ α(f) ⟨∘⟩ α(g)
``````````````````````````````````````````````````
and likewise for `γ`, where `⟨∘⟩ ` is composition in the Kleisli category for
the monad `M`.

`\begin{proposition}`{.raw}
`Sₜ[s] ∘ 𝒫ₜ α⇄γ 𝒫ₜ ∘ Sₜ[s]`.
`\end{proposition}`{.raw}
The proof is by calculation after unfolding the definitions.

## Flow Sensitivity Transformer

The flow sensitivity transformer is a unique monad transformer that combines
state and nondeterminism effects, and does not arise naturally from composing
vanilla nondeterminism and state transformers. The flow sensitivity transformer
is defined:
`````indent```````````````````````````````````````
FSₜ[_] : (Type → Type) → (Type → Type)
FSₜ[s](m)(α) := s → m([α ↦ s])
``````````````````````````````````````````````````
where `[α ↦ s]` is notation for a finite map over a defined domain in `α`.

`FSₜ[s]` is a monad when `s` is a join-semilattice and `m` is a
join-semilattice functor:
`````indent```````````````````````````````````````
bind : ∀ α β, 
  FSₜ[s](m)(α) → (α → FSₜ[s](m)(β)) → FSₜ[s](m)(β)
bind(m)(f)(s) := doₘ
  {x₁ ↦ s₁,..,xₙ ↦ sₙ} ←ₘ m(s)
  f(x₁)(s₁) ⟨+⟩ .. ⟨+⟩ f(xₙ)(sₙ)
return : ∀ α, α → FSₜ[s](m)(α)
return(x)(s) := returnₘ {x ↦ s}
``````````````````````````````````````````````````

`FSₜ[s]` has monadic state effects:
`````indent```````````````````````````````````````
get : FSₜ[s](m)(s)
get(s) := returnₘ {s ↦ s}
put : s → FSₜ[s](m)(1)
put(s')(s) := returnₘ {1 ↦ s'}
``````````````````````````````````````````````````

`FSₜ[s]` has nondeterminism effects when `s` is a join-semilattice and `m` is a
join-semilattice functor:
`````indent```````````````````````````````````````
mzero : ∀ α, FSₜ[s](m)(α)
mzero(s) := ⊥ₘ
_[⟨+⟩]_ : ∀ α, FSₜ[s](m)(α) x FSₜ[s](m)(α) → FSₜ[s](m)(α)
(m₁ ⟨+⟩ m₂)(s) := m₁(s) ⊔ₘ m₂(s)
``````````````````````````````````````````````````

The last property required for `FSₜ[s]` to fit into our framework is to map
monadic actions in `FSₜ[s]` to transitions in some state space transformer `Π`.
`````indent```````````````````````````````````````
mstep-γ : ∀ α β, 
  (α → FSₜ[s](m)(β)) → (Σₘ([α ↦ s]) → Σₘ([β × s]))
mstep-γ(f) := mstepₘ-γ(F)
  where F({x₁ ↦ s₁},..,{xₙ ↦ sₙ}) :=
    f(x₁)(s₁) ⟨+⟩ .. ⟨+⟩ f(xₙ)(sₙ)
``````````````````````````````````````````````````

`\begin{proposition}`{.raw}
`get` and `put` satisfy the state monad laws.
`\end{proposition}`{.raw}

`\begin{proposition}`{.raw}
`mzero` and `⟨+⟩` satisfy the nondeterminism monad laws.
`\end{proposition}`{.raw}

`\begin{proposition}`{.raw}
`Sₜ[s] ∘ 𝒫ₜ α₁⇄γ₁ FSₜ[s] α₂⇄γ₂ 𝒫ₜ ∘ Sₜ[s]`.
`\end{proposition}`{.raw}

These proofs are analagous to those for state and nondeterminism monad
transformers.

## Galois Transformers

The capstone of our compositional framework is the fact that monad transformers
`Sₜ[s]`, `FSₜ[s]` and `𝒫ₜ` are also _Galois transformers_. Whereas a monad
transformer is a functor between monads, a Galois transformer is a functor
between Galois monads.

`\begin{definition}`{.raw}
A monad transformer `T` is a Galois transformer if:

1. For all monads `m₁` and `m₂`, `m₁ α⇄γ m₂` implies `T(m₁) α⇄γ T(m₂)`
2. For all monads `m` and functors `Σ` there exists `Π` s.t. 
   `(α → m(β)) α⇄γ (Σ(α) → Σ(β)) ⇒ (α → T(m)(β)) α⇄γ (Π(Σ)(α) → Π(Σ)(β))`. 

`\end{definition}`{.raw}

`\begin{proposition}`{.raw}
`Sₜ[s]`, `FSₜ[s]` and `𝒫ₜ` are Galois transformers.
`\end{proposition}`{.raw}
The proofs were sketched earlier in Section
\ref{a-compositional-monadic-framework}.

## Building Transformer Stacks

We can now build monad transformer stacks from combinations of `Sₜ[s]`,
`FS[s]ₜ` and `𝒫ₜ` with the following properties:

- The resulting monad has the combined effects of all pieces of the transformer
  stack.
- Actions in the resulting monad map to a state space transition system `Σ → Σ`
  for some `Σ`, allowing one to execute the analysis.
- Galois connections between `CΣ` and `AΣ` are established piecewise from monad
  transformer components.
- Monad transformer components are proven correct for all possible languages
  and choices for orthogonal analysis features.

We instantiate our interpreter to the following monad stacks in decreasing
order of precision:

\vspace{1em}
`\begin{tabular}{l | l | l}`{.raw}
`````rawmacro````````````````````````````````````
Sₜ[AEnv]     & Sₜ[AEnv]      & Sₜ[AEnv]    \\
Sₜ[AKAddr]   & Sₜ[AKAddr]    & Sₜ[AKAddr]  \\
Sₜ[AKStore]  & Sₜ[AKStore]   & Sₜ[AKStore] \\
Sₜ[ATime]    & Sₜ[ATime]     & Sₜ[ATime]   \\
Sₜ[AStore]   &               & 𝒫ₜ          \\
𝒫ₜ           & FSₜ[AStore]   & Sₜ[AStore]  \\
``````````````````````````````````````````````````
`\end{tabular}`{.raw}
\vspace{1em}

\noindent
From left to right, these give path-sensitive, flow-sensitive, and
flow-insensitive analyses. Furthermore, each monad stack with abstract
components is assigned a Galois connection by-construction with their concrete
analogues:

\vspace{1em}
`\begin{tabular}{l | l | l}`{.raw}
`````rawmacro``````````````````````````````````````
Sₜ[CEnv]     & Sₜ[CEnv]      & Sₜ[CEnv]    \\
Sₜ[CKAddr]   & Sₜ[CKAddr]    & Sₜ[CKAddr]  \\
Sₜ[CKStore]  & Sₜ[CKStore]   & Sₜ[CKStore] \\
Sₜ[CTime]    & Sₜ[CTime]     & Sₜ[CTime]   \\
Sₜ[CStore]   &               & 𝒫ₜ          \\
𝒫ₜ           & FSₜ[CStore]   & Sₜ[CStore]  \\
`````````````````````````````````````````````````
`\end{tabular}`{.raw}
\vspace{1em}

Another benefit of our approach is that we can selectively widen the value and
continuation stores independent of each other. To do this we merely swap the
order of transformers:
\vspace{1em}
`\begin{tabular}{l | l | l}`{.raw}
`````rawmacro``````````````````````````````````````
Sₜ[CEnv]     & Sₜ[CEnv]      & Sₜ[CEnv]    \\
Sₜ[CKAddr]   & Sₜ[CKAddr]    & Sₜ[CKAddr]  \\
Sₜ[CTime]    & Sₜ[CTime]     & Sₜ[CTime]   \\
Sₜ[CStore]   & FSₜ[CStore]   & 𝒫ₜ          \\
𝒫ₜ           &               & Sₜ[CStore]  \\
Sₜ[CKStore]  & Sₜ[CKStore]   & Sₜ[CKStore] \\
`````````````````````````````````````````````````
`\end{tabular}`{.raw}
\vspace{1em}

# Implementation

We have implemented our framework in Haskell and applied it to compute analyses
for `λIF`. Our implementation provides path sensitivity, flow sensitivity, and
flow insensitivity as a semantics-independent monad library. The code shares a
striking resemblance with the math.

Our interpreter for `λIF` is parameterized as discussed in
Section`~\ref{analysis-parameters}`{.raw}. We express a valid analysis with the
following Haskell constraint:
`````indent```````````````````````````````````````
type Analysis(δ,μ,m) ∷ Constraint = 
  (AAM(μ),Delta(δ),AnalysisMonad(δ,μ,m))
``````````````````````````````````````````````````
Constraints `AAM(μ)` and `Delta(δ)` are interfaces for abstract time and the
abstract domain.

\noindent
The constraint `AnalysisMonad(m)` requires only that `m` has the required
effects:
`````indent```````````````````````````````````````
type AnalysisMonad(δ,μ,m) ∷ Constraint = (
   Monad(m(δ,μ)), 
   MonadNondeterminism(m(δ,μ)),
   MonadState⸤Env(μ)⸥(m(δ,μ)),
   MonadState⸤Store(δ,μ)⸥(m(δ,μ)),
   MonadState⸤Time(μ,Exp)⸥(m(δ,μ)))
``````````````````````````````````````````````````
Our interpreter is implemented against this interface and concrete and abstract
interpreters are recovered by instantiating `δ`, `μ` and `m`.

Using Galois transformers, we enable arbitrary composition of choices for
various analysis components. For example, our implementation, called `maam`
supports command-line flags for garbage collection, k-CFA, and path- and
flow sensitivity.
``````````````````````````````````````````````````
./maam --gc --CFA=0 --flow-sen prog.lam
``````````````````````````````````````````````````
These flags are implemented completely independent of one another, and their
combination is applied to a single parameterized monadic interpreter.
Furthermore, using Galois transformers allows us to prove each combination
correct in one fell swoop.

Our implementation is publicly available and can be installed as a cabal
package by executing:
``````````````````````````````````````````````````
cabal install maam
``````````````````````````````````````````````````

# Related Work

Program analysis comes in many forms such as points-to
\cite{dvanhorn:Andersen1994Program}, flow
\cite{dvanhorn:Jones:1981:LambdaFlow}, or shape analysis
\cite{dvanhorn:Chase1990Analysis}, and the literature is vast. (See
\citet{dvanhorn:hind-paste01,dvanhorn:Midtgaard2012Controlflow} for surveys.)
Much of the research has focused on developing families or frameworks of
analyses that endow the abstraction with a number of knobs, levers, and dials
to tune precision and compute efficiently (some examples include
\citet{dvanhorn:Shivers:1991:CFA, dvanhorn:nielson-nielson-popl97,
dvanhorn:Milanova2005Parameterized, davdar:van-horn:2010:aam}; there are many
more).  These parameters come in various forms with overloaded meanings such as
object- \cite{dvanhorn:Milanova2005Parameterized,
dvanhorn:Smaragdakis2011Pick}, context- \cite{dvanhorn:Sharir:Interprocedural,
dvanhorn:Shivers:1991:CFA}, path- \cite{davdar:das:2002:esp}, and heap-
\cite{davdar:van-horn:2010:aam} sensitivities, or some combination thereof
\cite{dvanhorn:Kastrinis2013Hybrid}.

These various forms can all be cast in the theory of abstraction
interpretation of \citet{dvanhorn:Cousot:1977:AI,
dvanhorn:Cousot1979Systematic} and understood as computable
approximations of an underlying concrete interpreter.  Our work
demonstrates that if this underlying concrete interpreter is written
in monadic style, monad transformers are a useful way to organize and
compose these various kinds of program abstractions in a modular and
language-independent way.  

This work is inspired by the combination of
\citeauthor{dvanhorn:Cousot:1977:AI}'s theory of abstract interpretation based
on Galois connections \citeyearpar{dvanhorn:Cousot:1977:AI,
dvanhorn:Cousot1979Systematic, dvanhorn:Cousot98-5},
\citeauthor{dvanhorn:Liang1995Monad}'s monad transformers for modular
interpreters \citeyearpar{dvanhorn:Liang1995Monad} and
\citeauthor{dvanhorn:Sergey2013Monadic}'s monadic abstract interpreters
\citeyearpar{dvanhorn:Sergey2013Monadic}, and continues in the tradition of
applying monads to programming language semantics pioneered by
\citet{davdar:Moggi:1989:Monads}.

\citet{dvanhorn:Liang1995Monad} first demonstrated how monad transformers could
be used to define building blocks for constructing (concrete) interpreters.
Their interpreter monad \mbox{\(\mathit{InterpM}\)} bears a strong resemblance
to ours.  We show this "building blocks" approach to interpreter construction
extends to \emph{abstract} interpreter construction, too, by using Galois
transfomers.  Moreover, we show that these monad transformers can be proved
sound via a Galois connection to their concrete counterparts, ensuring the
soundness of any stack built from sound blocks of Galois transformers.
Soundness proofs of various forms of analysis are notoriously brittle with
respect to language and analysis features.  A reusable framework of Galois
transformers offers a potential way forward for a modular metatheory of program
analysis.

\citet{dvanhorn:Cousot98-5} develops a "calculational approach" to analysis
design whereby analyses are not designed and then verified \emph{post facto}
but rather derived by positing an abstraction and calculating it through the
concrete interpreter using Galois connections.  These calculations are done by
hand.  Our approach offers a limited ability to automate the calculation
process by relying on monad transformers to combine different abstractions.

\citet{dvanhorn:Sergey2013Monadic} first introduced Monadic Abstract
Interpreters (MAI), in which interpreters are also written in monadic style and
variations in analysis are recovered through new monad implementations.
However, each monad in MAI is designed from scratch for a specific language to
have specific analysis properties.  The MAI work is analogous to monadic
interpreter of \citet{dvanhorn:Wadler1992Essence}, in which the monad structure
is monolithic and must be reconstructed for each new language feature. Our work
extends the ideas in MAI in a way that isolates each parameter to be
independent of others, similar to the approach of
\citet{dvanhorn:Liang1995Monad}.  We factor out the monad as a truly semantics
independent feature.  This factorization reveals an orthogonal tuning knob for
path  and flow sensitivity.  Even more, we give the user building blocks for
constructing monads that are correct and give the desired properties by
construction.  Our framework is also motivated by the needs of reasoning
formally about abstract interpreters, no mention of which is made in MAI.

We build directly on the work of Abstracting Abstract Machines (AAM) by
\citet{davdar:van-horn:2010:aam} in our parameterization of abstract time and
call-site sensitivity. More notably, we follow the AAM philosophy of
instrumenting a concrete semantics _first_ and performing a systematic
abstraction _second_. This greatly simplifies the Galois connection arguments
during systematic abstraction. However, this is at the cost of proving that the
instrumented semantics simulate the original concrete semantics.


# Conclusion

We have shown that \emph{Galois transfomers}, monad transfomers that form
Galois connections, are effective, language-inde\-pendent building blocks for
constructing program analyzers and form the basis of a modular, reusable, and
composable metatheory for program analysis.

In the end, we hope language independent characterizations of analysis
ingredients will both facilate the systematic construction of program analyses
and bridge the gap between various communities which often work in isolation.

-- We use the nondeterminism laws to reason about nondeterminism effects, w
-- `````indent```````````````````````````````````````
-- ⊥-zero₁ : bind(mzero)(k) = mzero
-- ⊥-zero₂ : bind(m)(λ(a).mzero) = mzero
-- ⊥-unit₁ : mzero ⟨+⟩ m = m
-- ⊥-unit₂ : m ⟨+⟩ mzero = m 
-- +-assoc : m₁ ⟨+⟩ (m₂ ⟨+⟩ m₃) = (m₁ ⟨+⟩ m₂) ⟨+⟩ m₃
-- +-comm : m₁ ⟨+⟩ m₂ = m₂ ⟨+⟩ m₁
-- +-dist : 
--   bind(m₁ ⟨+⟩ m₂)(k) = bind(m₁)(k) ⟨+⟩ bind(m₂)(k)
-- ``````````````````````````````````````````````````

-- `````indent``````````````````````````````````````` 
-- put-put : put(s₁) ; put(s₂) = put(s₂)
-- put-get : put(s) ; get = return(s)
-- get-put : s ← get ; put(s) = return(1)
-- get-get : s₁ ← get ; s₂ ← get ; k(s₁,s₂) = s ← get ; k(s,s)
-- ``````````````````````````````````````````````````

-- `\begin{figure}`{.raw}
-- \vspace{-1em}
-- `````align```````````````````````````````````````` 
--     M  : Type → Type
-- `````````````````````````````````````````````````` 
-- \caption{Nondeterminism Interface}
-- \label{NondeterminismInterface}
-- \vspace{-1em}
-- `\end{figure}`{.raw}

-- `````align````````````````````````````````````````
-- unit₁ :  bind(return(a))(k) = k(a)
-- unit₂ :  bind(m)(return) = m
-- assoc :  bind(bind(m)(k₁))(k₂) 
--       =  bind(m)(λ(a).bind(k₁(a))(k₂))
-- ``````````````````````````````````````````````````

-- --, despite the fruitful results of mapping between
-- langauge paradigms such as the work of \citet{dvanhorn:Might2010Resolving},
-- showing that object-oriented $k$-CFA can be applied to functional
-- languages to avoid the exponential time lower bound
-- \cite{dvanhorn:VanHorn-Mairson:ICFP08}.
