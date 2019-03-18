module tanya.memory.tests.mallocator;

version (TanyaNative)
{
}
else:

import tanya.memory.mallocator;

// Fails with false
@nogc nothrow pure @system unittest
{
    void[] p = Mallocator.instance.allocate(20);
    void[] oldP = p;
    assert(!Mallocator.instance.reallocate(p, size_t.max - 16));
    assert(oldP is p);
    Mallocator.instance.deallocate(p);
}

@nogc nothrow pure unittest
{
    assert(Mallocator.instance.alignment == (void*).alignof);
}