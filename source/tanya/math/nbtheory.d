/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * Number theory.
 *
 * Copyright: Eugene Wissner 2017-2020.
 * License: $(LINK2 https://www.mozilla.org/en-US/MPL/2.0/,
 *                  Mozilla Public License, v. 2.0).
 * Authors: $(LINK2 mailto:info@caraus.de, Eugene Wissner)
 * Source: $(LINK2 https://github.com/caraus-ecms/tanya/blob/master/source/tanya/math/nbtheory.d,
 *                 tanya/math/nbtheory.d)
 */
module tanya.math.nbtheory;

import tanya.meta.trait;
import tanya.meta.transform;

import core.math : fabs;
import std.math : log;

/**
 * Calculates the absolute value of a number.
 *
 * Params:
 *  T = Argument type.
 *  x = Argument.
 *
 * Returns: Absolute value of $(D_PARAM x).
 */
Unqual!T abs(T)(T x)
if (isIntegral!T)
{
    static if (isSigned!T)
    {
        return x >= 0 ? x : -x;
    }
    else
    {
        return x;
    }
}

///
@nogc nothrow pure @safe unittest
{
    int i = -1;
    assert(i.abs == 1);
    static assert(is(typeof(i.abs) == int));

    uint u = 1;
    assert(u.abs == 1);
    static assert(is(typeof(u.abs) == uint));
}

/// ditto
Unqual!T abs(T)(T x)
if (isFloatingPoint!T)
{
    return fabs(x);
}

///
@nogc nothrow pure @safe unittest
{
    float f = -1.64;
    assert(f.abs == 1.64F);
    static assert(is(typeof(f.abs) == float));

    double d = -1.64;
    assert(d.abs == 1.64);
    static assert(is(typeof(d.abs) == double));

    real r = -1.64;
    assert(r.abs == 1.64L);
    static assert(is(typeof(r.abs) == real));
}

/**
 * Calculates natural logarithm of $(D_PARAM x).
 *
 * Params:
 *  T = Argument type.
 *  x = Argument.
 *
 * Returns: Natural logarithm of $(D_PARAM x).
 */
Unqual!T ln(T)(T x)
if (isFloatingPoint!T)
{
    return log(x);
}

///
@nogc nothrow pure @safe unittest
{
    import tanya.math;

    assert(isNaN(ln(-7.389f)));
    assert(isNaN(ln(-7.389)));
    assert(isNaN(ln(-7.389L)));

    assert(isInfinity(ln(0.0f)));
    assert(isInfinity(ln(0.0)));
    assert(isInfinity(ln(0.0L)));

    assert(ln(1.0f) == 0.0f);
    assert(ln(1.0) == 0.0);
    assert(ln(1.0L) == 0.0L);
}
