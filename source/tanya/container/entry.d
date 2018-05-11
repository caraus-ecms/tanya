/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/*
 * Internal package used by containers that rely on entries/nodes.
 *
 * Copyright: Eugene Wissner 2016-2018.
 * License: $(LINK2 https://www.mozilla.org/en-US/MPL/2.0/,
 *                  Mozilla Public License, v. 2.0).
 * Authors: $(LINK2 mailto:info@caraus.de, Eugene Wissner)
 * Source: $(LINK2 https://github.com/caraus-ecms/tanya/blob/master/source/tanya/container/entry.d,
 *                 tanya/container/entry.d)
 */
module tanya.container.entry;

import tanya.algorithm.mutation;
import tanya.container.array;
import tanya.meta.trait;
import tanya.typecons;

package struct SEntry(T)
{
    // Item content.
    T content;

    // Next item.
    SEntry* next;
}

package struct DEntry(T)
{
    // Item content.
    T content;

    // Previous and next item.
    DEntry* next, prev;
}

package enum BucketStatus : byte
{
    deleted = -1,
    empty = 0,
    used = 1,
}

package struct Bucket(K, V = void)
{
    static if (is(V == void))
    {
        K key_;
    }
    else
    {
        alias KV = Pair!(K, "key", V, "value");
        KV kv;
    }
    BucketStatus status = BucketStatus.empty;

    this(ref K key)
    {
        this.key = key;
    }

    @property void key(ref K key)
    {
        this.key() = key;
        this.status = BucketStatus.used;
    }

    @property ref inout(K) key() inout
    {
        static if (is(V == void))
        {
            return this.key_;
        }
        else
        {
            return this.kv.key;
        }
    }

    bool opEquals(ref inout(K) key) inout
    {
        return this.status == BucketStatus.used && this.key == key;
    }

    bool opEquals(ref inout(typeof(this)) that) inout
    {
        return key == that.key && this.status == that.status;
    }

    void remove()
    {
        static if (hasElaborateDestructor!K)
        {
            destroy(key);
        }
        this.status = BucketStatus.deleted;
    }
}

// Possible sizes for the hash-based containers.
package static immutable size_t[33] primes = [
    0, 3, 7, 13, 23, 37, 53, 97, 193, 389, 769, 1543, 3079, 6151, 12289,
    24593, 49157, 98317, 196613, 393241, 786433, 1572869, 3145739, 6291469,
    12582917, 25165843, 50331653, 100663319, 201326611, 402653189,
    805306457, 1610612741, 3221225473
];

package struct HashArray(alias hasher, K, V = void)
{
    alias Key = K;
    alias Value = V;
    alias Bucket = .Bucket!(Key, Value);
    alias Buckets = Array!Bucket;

    Buckets array;
    size_t lengthIndex;
    size_t length;

    /*
     * Returns bucket position for `hash`. `0` may mean the 0th position or an
     * empty `buckets` array.
     */
    size_t locateBucket(ref const Key key) const
    {
        return this.array.length == 0 ? 0 : hasher(key) % this.array.length;
    }

    /*
     * Inserts a key into an empty or deleted bucket. If the key is
     * already in there, does nothing. Returns the bucket with the key.
     */
    ref Bucket insert(ref Key key)
    {
        while (true)
        {
            auto bucketPosition = locateBucket(key);

            foreach (ref e; this.array[bucketPosition .. $])
            {
                if (e == key)
                {
                    return e;
                }
                else if (e.status != BucketStatus.used)
                {
                    ++this.length;
                    return e;
                }
            }

            if (primes.length == (this.lengthIndex + 1))
            {
                this.array.insertBack(Bucket(key));
                return this.array[$ - 1];
            }
            if (this.rehashToSize(this.lengthIndex + 1))
            {
                ++this.lengthIndex;
            }
        }
    }

    // Takes an index in the primes array.
    bool rehashToSize(const size_t n)
    in
    {
        assert(n < primes.length);
    }
    do
    {
        auto storage = typeof(this.array)(primes[n], this.array.allocator);
        DataLoop: foreach (ref e1; this.array[])
        {
            if (e1.status == BucketStatus.used)
            {
                auto bucketPosition = hasher(e1.key) % storage.length;

                foreach (ref e2; storage[bucketPosition .. $])
                {
                    if (e2.status != BucketStatus.used) // Insert the key
                    {
                        e2 = e1;
                        continue DataLoop;
                    }
                }
                return false; // Rehashing failed.
            }
        }
        move(storage, this.array);
        return true;
    }

    void rehash(const size_t n)
    {
        size_t lengthIndex;
        for (; lengthIndex < primes.length; ++lengthIndex)
        {
            if (primes[lengthIndex] >= n)
            {
                break;
            }
        }
        if (this.rehashToSize(lengthIndex))
        {
            this.lengthIndex = lengthIndex;
        }
    }

    @property size_t capacity() const
    {
        return this.array.length;
    }

    void clear()
    {
        this.array.clear();
        this.length = 0;
    }

    size_t remove(ref Key key)
    {
        auto bucketPosition = locateBucket(key);
        foreach (ref e; this.array[bucketPosition .. $])
        {
            if (e == key) // Found.
            {
                e.remove();
                --this.length;
                return 1;
            }
            else if (e.status == BucketStatus.empty)
            {
                break;
            }
        }
        return 0;
    }

    bool canFind(ref const Key key) const
    {
        auto bucketPosition = locateBucket(key);
        foreach (ref e; this.array[bucketPosition .. $])
        {
            if (e == key) // Found.
            {
                return true;
            }
            else if (e.status == BucketStatus.empty)
            {
                break;
            }
        }
        return false;
    }
}
