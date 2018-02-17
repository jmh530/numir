module numir.stats;

import std.traits : isUnsigned;
import mir.math.sum : Summation;
import mir.ndslice.slice : isSlice;

/++
Count number of occurrences of each value in slice of non-negative ints.

Params:
    xs = input slice
    minlength = a minimum number of bins for the output array

Returns:
    size_t slice of number of ocurrence

TODO:
    support @nogc
 +/
auto bincount(T)(T xs, size_t minlength=0) pure if (isUnsigned!(typeof(xs.front)) && isSlice!T)
{
    import mir.ndslice.algorithm : each;
    import numir.core : zeros, resize;

    auto ret = zeros!size_t(minlength);
    auto maxx = minlength;
    xs.each!((x) {
        if (ret.length < x+1) {
            maxx = x+1;
            ret = ret.resize(x+1);
        }
        ret[x] += 1;
    });
    return ret[0 .. maxx];
}

/++
Count weighted number of occurrences of each value in slice of non-negative ints.
Note that empty weight causes compiler error.

Params:
    xs = input slice
    weights = weights slice of the same length as `xs`
    minlength = a minimum number of bins for the output array

Returns:
    slice like weights of weighted number of ocurrences

TODO:
    support @nogc
 +/
auto bincount(T, W)(T xs, W weights, size_t minlength=0) pure if (isUnsigned!(typeof(xs.front)) && isSlice!T  && isSlice!W)
in
{
    assert(xs.length == weights.length);
}
do
{
    import numir.core : zeros, resize;
    import mir.ndslice.slice : DeepElementType;

    alias D = DeepElementType!(typeof(weights));
    auto wsh = weights.shape;
    wsh[0] = minlength;
    auto ret = zeros!D(wsh);
    size_t maxx = 0;
    // TODO use mir.ndslice.algorithm.each
    foreach (i; 0 .. xs.length) {
        auto x = xs[i];
        if (ret.length < x+1) {
            maxx = x+1;
            ret = ret.resize(x+1);
        }
        ret[x][] += weights[i];
    }
    return ret[0 .. maxx];
}

///
unittest
{
    import numir : bincount, nparray;
    import mir.ndslice.slice : sliced;

    auto ys = [0, 1, 1, 0, 1].sliced!size_t;
    assert(ys.bincount == [2, 3]);
    assert(ys.bincount([[1, 0], [-1, 0], [-1, 0], [1, 0], [-1, 0]].nparray) == [[2, 0], [-3,0]]);
    assert([].sliced!size_t.bincount == [].sliced!size_t);
    // FIXME
    // assert([].sliced!size_t.bincount([].sliced!double) == [].sliced!double);
}


/++
Compute mean over all the elements in an input slice `xs`.

Params:
    xs = input slice

Returns:
    Result (default: double) scalar mean
 +/
@nogc auto mean(Summation algorithm=Summation.appropriate, Result=double, Xs)(Xs xs) pure
{
    import mir.math.sum : sum;
    import mir.ndslice.topology : as;
    import numir : size;
    return xs.as!Result.sum!algorithm / xs.size;
}

template toSummation(string s) {
    mixin("enum toSummation = Summation." ~ s ~ ";");
}

///ditto
@nogc auto mean(string algorithm, Result=double, Xs)(Xs xs) pure
{
    return mean!(toSummation!algorithm, Result, Xs)(xs);
}

///
pure @nogc @safe
unittest
{
    import numir : mean;
    import mir.ndslice : iota;
    /*
      [[0,1,2],
       [3,4,5]]
     */
    assert(iota(2, 3).mean == (5.0 / 2.0));
    assert(iota(2, 3).mean!"fast" == (5.0 / 2.0));
}

/++
Similar to `mir.ndslice.topology.byDim` but `alongDim` does transposed and pack on the input slice along `dim`

Params:
    s = input slice

Returns:
    s.transposed(0 .. Ndim!S, dim).pack!1
 +/
auto alongDim(ptrdiff_t dim, S)(S s) if (isSlice!S)
{
    import numir.core.utility : Ndim;
    enum n = Ndim!S;
    enum a = dim >= 0 ? dim : n + dim;
    static assert(a < n);

    import std.range : iota;
    import std.array : array;
    import mir.ndslice.dynamic : transposed;
    import mir.ndslice.topology : pack;

    enum size_t[n] ds = iota(0, a).array ~ iota(a+1, n).array ~ [a];
    return s.transposed(ds).pack!1;
}

/++
Compute mean of an input slice `xs` along `axis`.
Note that `axis` can be negative: -n = xs.ndim-n

Params:
    xs = input slice

Returns:
    mean slice with the same shape to `xs` except for `axis` that has the element type of Result (default: double)
 +/
auto mean(ptrdiff_t axis, Result=double, Xs)(Xs xs) pure
out(ret)
{
    import numir.core : Ndim;
    enum a = axis >= 0 ? axis : Ndim!Xs + axis;
    static foreach (d; 0 .. a) {
        assert(ret.length!d == xs.length!d);
    }
    static foreach (d; a+1 .. Ndim!Xs) {
        assert(ret.length!(d-1) == xs.length!d);
    }
}
do
{
    import mir.ndslice.algorithm : reduce;
    import mir.ndslice.topology : map, as;

    return xs.alongDim!axis.map!(x => reduce!((a, b) => a + b)(Result(0.0), x.as!Result) / x.length);
}

///
pure @safe @nogc
unittest
{
    import numir : mean;
    import mir.ndslice : iota, as;
    /*
      [[0,1,2],
       [3,4,5]]
     */
    assert(iota(2, 3).mean!"fast" == (5.0 / 2.0));
    // [(0.0+3.0)/2.0, (1.0+4.0)/2.0, (2.0+5.0)/2.0]);
    assert(iota(2, 3).mean!0 == iota([3], 3, 2).as!double / 2.0);
    assert(iota(2, 3).mean!(-2) == iota([3], 3, 2).as!double / 2.0);
    // [(0.0+1.0+2.0)/3.0, (3.0+4.0+5.0)/3.0]);
    assert(iota(2, 3).mean!1 == iota([2], 3, 9).as!double / 3.0);
    assert(iota(2, 3).mean!(-1) == iota([2], 3, 9).as!double / 3.0);
    assert(iota(2, 3, 4, 5).mean!0 == iota([3, 4, 5], 3 * 4 * 5 / 2));
}


/++
Compute variance over all the elements in an input slice `xs`.

Params:
    xs = input slice

Returns:
    Result (default: double) scalar variance

See_Also:
    faster eq., https://wikimedia.org/api/rest_v1/media/math/render/svg/67c38600b240e9bf9479466f5f362792e4fc4fb8
    discussion, https://github.com/libmir/numir/pull/22
 +/
pure auto var(Summation algorithm=Summation.appropriate, bool faster=false, Result=double, X)(X x) if (isSlice!X)
{
    static if (faster)
    {
        // NOTE maybe unstable
        return (x ^^ 2.0).mean!(algorithm, Result) - (x.mean!(algorithm, Result)) ^^ 2.0;
    }
    else
    {
        return ((x - x.mean!(algorithm, Result)) ^^ 2.0).mean!(algorithm, Result);
    }
}

///ditto
pure auto var(string algorithm, bool faster=false, Result=double, X)(X x) if (isSlice!X)
{
    return x.var!(toSummation!algorithm, faster, Result);
}

///
pure @safe @nogc unittest
{
    import mir.ndslice : iota;
    import numir : var;
    /*
      [[1, 2],
       [3, 4]]
     */
    assert(iota([2, 2], 1).var == 1.25);
    assert(iota([2, 2], 1).var!"fast" == 1.25);
    assert(iota([2, 2], 1).var!("fast", true) == 1.25);
}


/++
Compute variance of an input slice `xs` along `axis`.
Note that `axis` can be negative: -n = xs.ndim-n

Params:
    xs = input slice

Returns:
    variance slice with the same shape to `xs` except for `axis` that has the element type of Result (default: double)

See_Also:
    faster eq., https://wikimedia.org/api/rest_v1/media/math/render/svg/67c38600b240e9bf9479466f5f362792e4fc4fb8
    discussion, https://github.com/libmir/numir/pull/22

TODO:
    support @nogc
 +/
pure auto var(ptrdiff_t axis, bool faster=false, Result=double, Xs)(Xs xs) if (isSlice!Xs)
{
    import numir.core.creation : zeros;
    import mir.ndslice : swapped, slice;

    static if (faster)
    {
        // NOTE maybe unstable
        return (xs ^^ 2.0).mean!(axis, Result) - xs.mean!(axis, Result) ^^ 2.0;
    }
    else
    {
        // TODO make this @nogc
        import numir.core.creation : zeros;
        import mir.ndslice : swapped;
        import numir.core : Ndim;
        enum a = axis >= 0 ? axis : Ndim!Xs + axis;

        auto m = xs.mean!(a, Result);
        auto xt = xs.swapped!(0, a);
        auto xm = zeros!Result(xt.shape);
        foreach (i; 0 .. xt.length)
        {
            xm[i][] = xt[i] - m;
        }
        return (xm ^^ 2.0).mean!(0, Result);
    }
}


///
pure @safe
unittest
{
    import mir.ndslice : iota;
    import numir : var;
    /*
      [[1, 2],
       [3, 4]]
     */
    assert(iota([2, 2], 1).var!0 == [1.0, 1.0]);
    assert(iota([2, 2], 1).var!1 == [0.25, 0.25]);
    assert(iota([2, 2], 1).var!(-2) == [1.0, 1.0]);
    assert(iota([2, 2], 1).var!(-1) == [0.25, 0.25]);
    assert(iota([2, 3], 1).var!0 == [2.25, 2.25, 2.25]);
    assert(iota([2, 3], 1).var!(-2) == [2.25, 2.25, 2.25]);
}

///
pure @safe @nogc
unittest
{
    import mir.ndslice : iota, as;
    import numir : var;
    /*
      [[1, 2],
       [3, 4]]
     */
    // [1.0, 1.0]
    assert(iota([2, 2], 1).var!(0, true) == iota([2], 1, 0));
    // [0.25, 0.25]
    assert(iota([2, 2], 1).var!(1, true) == iota([2], 1, 0).as!double / 4.0);
    // [1.0, 1.0]
    assert(iota([2, 2], 1).var!(-2, true) == iota([2], 1, 0));
    // [0.25, 0.25]
    assert(iota([2, 2], 1).var!(-1, true) == iota([2], 1, 0).as!double / 4.0);

    assert(iota([2, 3], 1).var!(0, true) == iota([3], 1, 0).as!double * 2.25);
    assert(iota([2, 3], 1).var!(-2, true) == iota([3], 1, 0).as!double * 2.25);
}
