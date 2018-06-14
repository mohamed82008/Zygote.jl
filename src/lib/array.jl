grad(xs::Array) = grad.(xs)

@inline _forward(::Context, ::Type{T}, args...) where T<:Array = T(args...), Δ -> nothing

@grad Base.vect(xs...) = Base.vect(xs...), Δ -> (Δ...,)

@grad function getindex(xs::Array, i...)
  xs[i...], function (Δ)
    Δ′ = zero(xs)
    Δ′[i...] = Δ
    (Δ′, map(_ -> nothing, i)...)
  end
end

@grad a::AbstractVecOrMat * b::AbstractVecOrMat =
  a * b, Δ -> (Δ * transpose(b), transpose(a) * Δ)

@grad sum(xs::AbstractArray, dim...) =
  sum(xs, dim...), Δ -> (similar(xs) .= Δ, map(_->nothing, dim)...)

#                        .-'''-.                               _..._
#                       '   _    \         _______          .-'_..._''.
#  /|                 /   /` '.   \        \  ___ `'.     .' .'      '.\
#  ||                .   |     \  '         ' |--.\  \   / .'
#  ||        .-,.--. |   '      |  '        | |    \  ' . '                                     .|
#  ||  __    |  .-. |\    \     / /  __     | |     |  '| |                 __                .' |_
#  ||/'__ '. | |  | | `.   ` ..' /.:--.'.   | |     |  || |              .:--.'.         _  .'     |
#  |:/`  '. '| |  | |    '-...-'`/ |   \ |  | |     ' .'. '             / |   \ |      .' |'--.  .-'
#  ||     | || |  '-             `" __ | |  | |___.' /'  \ '.          .`" __ | |     .   | / |  |
#  ||\    / '| |                  .'.''| | /_______.'/    '. `._____.-'/ .'.''| |   .'.'| |// |  |
#  |/\'..' / | |                 / /   | |_\_______|/       `-.______ / / /   | |_.'.'.-'  /  |  '.'
#  '  `'-'`  |_|                 \ \._,\ '/                          `  \ \._,\ '/.'   \_.'   |   /
#                                 `--'  `"                               `--'  `"             `'-'

using ForwardDiff: Dual, partials

dualify(x, ps) = x
dualify(x::Real, ps) = Dual(x, ps)
dualify(xs::AbstractArray{<:Real}, ps) = dualify.(xs, (ps,))

trim(x, Δ) = reshape(Δ, ntuple(i -> size(Δ, i), Val{ndims(x)}))

unbroadcast(x::AbstractArray, Δ) =
  size(x) == size(Δ) ? Δ :
    trim(x, sum(Δ, filter(n -> size(x, n) == 1, 1:ndims(Δ))))

unbroadcast(x::Number, Δ) = sum(Δ)

function getpartial(Δ, x, i)
  @inbounds p = getindex(partials(x), i)
  return Δ * p
end

@grad function broadcast(f, args::Vararg{Any,N}) where N
  dargs = map((x,i) -> dualify(x, ntuple(j -> i==j, Val(N))),
              args, ntuple(identity, Val(N)))
  out = broadcast(f, dargs...)
  (x -> x.value).(out), function (Δ)
    Δxs = ntuple(i -> getpartial.(Δ, out, i), Val(N))
    (nothing, unbroadcast.(args, Δxs)...)
  end
end