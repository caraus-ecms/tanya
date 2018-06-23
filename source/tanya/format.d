/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * This package doesn't yet contain public symbols. Refer to
 * $(D_PSYMBOL tanya.conv) for basic formatting and conversion functionality.
 *
 * Copyright: Eugene Wissner 2017-2018.
 * License: $(LINK2 https://www.mozilla.org/en-US/MPL/2.0/,
 *                  Mozilla Public License, v. 2.0).
 * Authors: $(LINK2 mailto:info@caraus.de, Eugene Wissner)
 * Source: $(LINK2 https://github.com/caraus-ecms/tanya/blob/master/source/tanya/format/package.d,
 *                 tanya/format/package.d)
 */
module tanya.format;

import tanya.container.string;
import tanya.encoding.ascii;
import tanya.math;
import tanya.memory.op;
import tanya.meta.metafunction;
import tanya.meta.trait;
import tanya.meta.transform;
import tanya.range.array;
import tanya.range.primitive;

// Returns the last part of buffer with converted number.
package(tanya) char[] integral2String(T)(T number, return ref char[21] buffer)
@trusted
if (isIntegral!T)
{
    // abs the integer.
    ulong n64 = number < 0 ? -cast(long) number : number;

    char* start = buffer[].ptr + buffer.sizeof - 1;

    while (true)
    {
        // Do in 32-bit chunks (avoid lots of 64-bit divides even with constant
        // denominators).
        char* o = start - 8;
        uint n;
        if (n64 >= 100000000)
        {
            n = n64 % 100000000;
            n64 /= 100000000;
        }
        else
        {
            n = cast(uint) n64;
            n64 = 0;
        }

        while (n)
        {
            *--start = cast(char) (n % 10) + '0';
            n /= 10;
        }
        // Ignore the leading zero if it was the last part of the integer.
        if (n64 == 0)
        {
            if ((start[0] == '0')
             && (start != (buffer[].ptr + buffer.sizeof -1)))
            {
                ++start;
            }
            break;
        }
        // Copy leading zeros if it wasn't the most significant part of the
        // integer.
        while (start != o)
        {
            *--start = '0';
        }
    }

    // Get the length that we have copied.
    uint l = cast(uint) ((buffer[].ptr + buffer.sizeof - 1) - start);
    if (l == 0)
    {
        *--start = '0';
        l = 1;
    }
    else if (number < 0) // Set the sign.
    {
        *--start = '-';
        ++l;
    }

    return buffer[$ - l - 1 .. $ - 1];
}

// Converting an integer to string.
@nogc nothrow pure @system unittest
{
    char[21] buf;

    assert(integral2String(80, buf) == "80");
    assert(integral2String(-80, buf) == "-80");
    assert(integral2String(0, buf) == "0");
    assert(integral2String(uint.max, buf) == "4294967295");
    assert(integral2String(int.min, buf) == "-2147483648");
}

private int frexp(const double x) @nogc nothrow pure @safe
{
    const FloatBits!double bits = { x };
    const int biased = (bits.integral & 0x7fffffffffffffffUL) >> 52;

    if ((bits.integral << 1) == 0 || biased == 0x7ff) // 0, NaN of Infinity
    {
        return 0;
    }
    else if (biased == 0) // Subnormal, normalize the exponent
    {
        return frexp(x * 0x1p64) - 64;
    }

    return biased - 1022;
}

/*
 * Double-double high-precision floating point number.
 *
 * The first element is a base value corresponding to the nearest approximation
 * of the target $(D_PSYMBOL HP) value, and the second element is an offset
 * value corresponding to the difference between the target value and the base.
 * Thus, the $(D_PSYMBOL HP) value represented is the sum of the base and the
 * offset.
 */
private struct HP
{
    double base;
    double offset = 0.0;

    this(double base, double offset = 0.0) @nogc nothrow pure @safe
    {
        this.base = base;
        this.offset = offset;
    }

    void normalize() @nogc nothrow pure @safe
    {
        const double target = this.base + this.offset;
        this.offset -= target - this.base;
        this.base = target;
    }

    void multiplyBy10() @nogc nothrow pure @safe
    {
        const double h = 8 * this.base + 2 * this.base;
        const double l = 10 * this.offset;
        const double c = (h - 8 * this.base) - 2 * this.base;

        this.base = h;
        this.offset = l - c;

        normalize();
    }

    void divideBy10() @nogc nothrow pure @safe
    {
        const double h = this.base / 10.0;
        const double l = this.offset / 10.0;
        const double c = (this.base - 8.0 * h) - 2.0 * h;

        this.base = h;
        this.offset = l + c / 10.0;

        normalize();
    }

    HP opBinary(string op : "*")(const double value) const
    {
        HP factor1 = split(this.base);
        HP factor2 = split(value);

        const double base = this.base * value;
        const double offset = (factor1.base * factor2.base - base)
                            + factor1.base * factor2.offset
                            + factor1.offset * factor2.base
                            + factor1.offset * factor2.offset;

        return HP(base, this.offset * value + offset);
    }
}

/*
 * Splits a double into two FP numbers.
 */
private HP split(double x) @nogc nothrow pure @safe
{
    FloatBits!double bits = { x };
    bits.integral &= 0xfffffffff8000000UL;
    return HP(bits.floating , x - bits.floating);
}

private enum special = 0x7000;
private enum char period = '.';

// Error factor. Determines the width of the narrow and wide intervals.
private enum double epsilon = 8.78e-15;

private immutable HP[600] powersOf10 = [
    HP(1e308, -0x1.c2a3c3d855605p+966),
    HP(1e307, 0x1.cab0301fbbb2ep+963),
    HP(1e306, -0x1.c43fd98036a40p+960),
    HP(1e305, 0x1.3f266e198eabfp+959),
    HP(1e304, 0x1.fea3e35c17799p+955),
    HP(1e303, -0x1.167d4fed38558p+944),
    HP(1e302, -0x1.9a78643ff0f9dp+949),
    HP(1e301, -0x1.c3f3d399818fcp+945),
    HP(1e300, -0x1.698fdc7ace0cap+942),
    HP(1e299, -0x1.213fe39571a3bp+939),
    HP(1e298, 0x1.646693ddb093ap+935),
    HP(1e297, -0x1.f1eaf3a0fe277p+930),
    HP(1e296, 0x1.a4dda37f34ad3p+927),
    HP(1e295, 0x1.50b14f98f6f0fp+924),
    HP(1e294, -0x1.dfb9135c6a060p+922),
    HP(1e293, 0x1.b36bf082de619p+919),
    HP(1e292, -0x1.ea19fcba70c29p+913),
    HP(1e291, 0x1.3794670de972ap+912),
    HP(1e290, -0x1.6d22e0c1aba44p+909),
    HP(1e289, -0x1.241be701561d0p+906),
    HP(1e288, -0x1.ce31f3444e400p+899),
    HP(1e287, -0x1.c7d1cb86d4a00p+899),
    HP(1e286, -0x1.3fb6127154333p+895),
    HP(1e285, 0x1.33a97c177947ap+891),
    HP(1e284, -0x1.eb55ce5d02b02p+889),
    HP(1e283, 0x1.baa9e904c87fcp+885),
    HP(1e282, -0x1.0444df2f5f99cp+882),
    HP(1e281, -0x1.a06e31e565c2dp+878),
    HP(1e280, -0x1.4d24f4b7849bdp+875),
    HP(1e279, -0x1.d750c3c603afep+872),
    HP(1e278, 0x1.dab1f9f660802p+868),
    HP(1e277, -0x1.dd804d47f9974p+861),
    HP(1e276, -0x1.b1799d76cc7acp+862),
    HP(1e275, 0x1.0b9eb53a8f9dcp+859),
    HP(1e274, 0x1.a2e55dc872e4ap+856),
    HP(1e273, 0x1.d16efc73eb076p+852),
    HP(1e272, -0x1.beda693cdd93ap+849),
    HP(1e271, 0x1.00eadf0281f04p+846),
    HP(1e270, -0x1.9821ce62634c6p+842),
    HP(1e269, -0x1.468171e84f704p+839),
    HP(1e268, 0x1.28ca7cf2b4191p+835),
    HP(1e267, 0x1.dadd94b7868e9p+831),
    HP(1e266, -0x1.b74ebc39fac12p+828),
    HP(1e265, -0x1.7c85e4e3fde6dp+826),
    HP(1e264, -0x1.94096e39963e2p+822),
    HP(1e263, -0x1.d9b7c71ead93bp+817),
    HP(1e262, -0x1.7af96c188adc9p+814),
    HP(1e261, 0x1.4dce1d94b1071p+813),
    HP(1e260, -0x1.e9e96a454b27dp+809),
    HP(1e259, 0x1.ab4544955d79bp+806),
    HP(1e258, -0x1.109562bbb5383p+803),
    HP(1e257, -0x1.ceaad58bdd80cp+798),
    HP(1e256, -0x1.7222446fe4670p+795),
    HP(1e255, 0x1.c5f8be99f1e99p+790),
    HP(1e254, 0x1.f464f2eb96c85p+789),
    HP(1e253, 0x1.9050c2561239dp+786),
    HP(1e252, -0x1.f2f297bb249e8p+783),
    HP(1e251, -0x1.84b7592b6dca6p+779),
    HP(1e250, 0x1.fc3a1f1074f7ap+776),
    HP(1e249, 0x1.9694e5a6c3f95p+773),
    HP(1e248, -0x1.75782a28600aap+769),
    HP(1e247, 0x1.3b9fde4619910p+766),
    HP(1e246, -0x1.69e6816185258p+763),
    HP(1e245, -0x1.763d9bcf3b6f4p+759),
    HP(1e244, -0x1.f831497295f2ap+756),
    HP(1e243, -0x1.935aa12877f54p+753),
    HP(1e242, -0x1.b89101da59887p+749),
    HP(1e241, -0x1.6074017b7ad39p+746),
    HP(1e240, -0x1.34a66b24bc3eap+741),
    HP(1e239, 0x1.455c215ed2ceep+737),
    HP(1e238, -0x1.58872c86a2a36p+736),
    HP(1e237, 0x1.52c70f944ab07p+733),
    HP(1e236, -0x1.e1f4b3df887f4p+729),
    HP(1e235, -0x1.81908fe606cc3p+726),
    HP(1e234, -0x1.9e9b661348f3dp+721),
    HP(1e233, 0x1.e783ae56f8d68p+718),
    HP(1e232, -0x1.a364ed76cfaa3p+716),
    HP(1e231, -0x1.4f83f12bd954fp+713),
    HP(1e230, -0x1.d9365a897aaa5p+710),
    HP(1e229, 0x1.f07b792044482p+703),
    HP(1e228, 0x1.cb3f8c1cd3a0dp+703),
    HP(1e227, -0x1.c3cd298289e5bp+700),
    HP(1e226, 0x1.2d1e23fbf02a0p+696),
    HP(1e225, 0x1.bdb1b66326880p+693),
    HP(1e224, 0x1.2f82bd6b70d99p+689),
    HP(1e223, -0x1.73976876d8eb8p+686),
    HP(1e222, -0x1.2945ed2be0bc6p+683),
    HP(1e221, -0x1.dba31513012d7p+679),
    HP(1e220, 0x1.d172257324207p+672),
    HP(1e219, 0x1.c82503beb6d00p+672),
    HP(1e218, -0x1.aff131b3b6dffp+670),
    HP(1e217, 0x1.4ce47d46db666p+666),
    HP(1e216, -0x1.1e926ac1d428ep+662),
    HP(1e215, 0x1.f3c56ee5ab22dp+660),
    HP(1e214, 0x1.8608b16f7837bp+656),
    HP(1e213, 0x1.ace89e3180b25p+651),
    HP(1e212, 0x1.ef61b93d19bd4p+650),
    HP(1e211, 0x1.7f02c1fb5c620p+646),
    HP(1e210, 0x1.ff3567fc49e80p+643),
    HP(1e209, -0x1.9a3baccfc4dffp+640),
    HP(1e208, 0x1.45a7709a56ccdp+635),
    HP(1e207, -0x1.17569fc243ae0p+633),
    HP(1e206, -0x1.bef0ff9d39167p+629),
    HP(1e205, -0x1.318198fb8e8a5p+625),
    HP(1e204, 0x1.4a63d8071bef6p+621),
    HP(1e203, 0x1.084fe005aff2bp+618),
    HP(1e202, 0x1.ce76600123308p+617),
    HP(1e201, -0x1.1c0f6664947f2p+613),
    HP(1e200, 0x1.6cb428f8ac016p+609),
    HP(1e199, -0x1.d484bc6954cc3p+607),
    HP(1e198, -0x1.0e758e1ddc272p+602),
    HP(1e197, 0x1.2d6a93f40e56bp+600),
    HP(1e196, 0x1.e2441fece3bdfp+596),
    HP(1e195, 0x1.6a06997b05fccp+592),
    HP(1e194, 0x1.5d9c3d6468cb8p+590),
    HP(1e193, -0x1.4eb6354945c39p+587),
    HP(1e192, -0x1.4abd220ed605cp+583),
    HP(1e191, -0x1.d5641b3f119e3p+580),
    HP(1e190, -0x1.778348ff414b5p+577),
    HP(1e189, -0x1.7e70e99737579p+572),
    HP(1e188, -0x1.31f3ee1292ac7p+569),
    HP(1e187, 0x1.ec04d3f892216p+567),
    HP(1e186, 0x1.59a90cb506d15p+562),
    HP(1e185, 0x1.14873d5d9f0ddp+559),
    HP(1e184, -0x1.78c1376a34b69p+555),
    HP(1e183, 0x1.cfb2b6a251508p+553),
    HP(1e182, -0x1.c03dd44af225fp+550),
    HP(1e181, 0x1.cc9b562a717b3p+547),
    HP(1e180, -0x1.48eaa556c351bp+541),
    HP(1e179, 0x1.16088aaa1845bp+539),
    HP(1e178, -0x1.2a62fbbbf64a8p+537),
    HP(1e177, -0x1.0f464b195b767p+531),
    HP(1e176, -0x1.b20a11c22bf0cp+527),
    HP(1e175, 0x1.6e32316c9534bp+527),
    HP(1e174, -0x1.4171720f88a29p+524),
    HP(1e173, -0x1.a2d60d303743fp+518),
    HP(1e172, -0x1.ed5e02a33e40cp+517),
    HP(1e171, 0x1.b769956135febp+513),
    HP(1e170, -0x1.06debbb23b343p+510),
    HP(1e169, 0x1.941a9d0b03d63p+507),
    HP(1e168, 0x1.43487da269782p+504),
    HP(1e167, -0x1.2df26a2f573fbp+500),
    HP(1e166, 0x1.74d7ab0d53cd0p+497),
    HP(1e165, 0x1.f712ef3ddca40p+494),
    HP(1e164, -0x1.c9035a0712651p+485),
    HP(1e163, 0x1.8e2cb7596c571p+487),
    HP(1e162, 0x1.3e8a2c4789df4p+484),
    HP(1e161, -0x1.358952c0bd012p+480),
    HP(1e160, -0x1.56a2119e533acp+474),
    HP(1e159, 0x1.775631702ae08p+474),
    HP(1e158, 0x1.8bbd1be6ab00dp+470),
    HP(1e157, 0x1.bf29f2e22335dp+465),
    HP(1e156, 0x1.65bb28b4e8f7ep+462),
    HP(1e155, -0x1.eda91756b019fp+457),
    HP(1e154, -0x1.fc5504aaf0053p+456),
    HP(1e153, 0x1.7797bb9ffdecbp+446),
    HP(1e152, -0x1.9740a6d3ccd01p+450),
    HP(1e151, -0x1.e40215d8f5cd2p+445),
    HP(1e150, 0x1.affe54ec0828ap+442),
    HP(1e149, -0x1.b99a446e6322fp+440),
    HP(1e148, -0x1.614836beb5b58p+437),
    HP(1e147, 0x1.fbe5b73754216p+432),
    HP(1e146, 0x1.326124a4aa6d1p+431),
    HP(1e145, 0x1.426db7510f86fp+425),
    HP(1e144, -0x1.18a0e9df93639p+423),
    HP(1e143, -0x1.c1017632856c2p+419),
    HP(1e142, -0x1.8066fc14355e7p+417),
    HP(1e141, -0x1.9ae326a7112e5p+412),
    HP(1e140, -0x1.1efa3aee36a2dp+411),
    HP(1e139, -0x1.fcba562d7ba2cp+406),
    HP(1e138, -0x1.96fb782462e89p+403),
    HP(1e137, -0x1.4595f9b6b586ep+400),
    HP(1e136, -0x1.d144c7c55e058p+397),
    HP(1e135, 0x1.e45ec05dcff72p+393),
    HP(1e134, 0x1.8e8c4cf2532fap+391),
    HP(1e133, -0x1.6b0bd69229010p+386),
    HP(1e132, 0x1.dca6eaf916630p+381),
    HP(1e131, 0x1.c943e44c1bd6bp+381),
    HP(1e130, -0x1.f12cf91fd3754p+377),
    HP(1e129, 0x1.7b80b0047445dp+369),
    HP(1e128, -0x1.901cc86649e4ap+371),
    HP(1e127, 0x1.7fd1f28f89c55p+367),
    HP(1e126, 0x1.ffdb2872d49dep+364),
    HP(1e125, 0x1.997c205bdd4b1p+361),
    HP(1e124, 0x1.c26033c62ede9p+357),
    HP(1e123, 0x1.370052d6b1641p+353),
    HP(1e122, -0x1.4199150ee42c9p+349),
    HP(1e121, -0x1.4d706ed2c1ab7p+347),
    HP(1e120, 0x1.1db281e1fd541p+343),
    HP(1e119, 0x1.3f1433f3feee6p+341),
    HP(1e118, 0x1.31b9ecb997e3ep+337),
    HP(1e117, -0x1.71d1a90520167p+334),
    HP(1e116, -0x1.6c38834399e18p+329),
    HP(1e115, -0x1.23606902e1813p+326),
    HP(1e114, -0x1.d233db37cf353p+322),
    HP(1e113, -0x1.74f648f97290fp+319),
    HP(1e112, 0x1.4f01f167b5e30p+318),
    HP(1e111, 0x1.4b364f0c56380p+314),
    HP(1e110, -0x1.2142b4b90fa66p+310),
    HP(1e109, 0x1.6462120b1a28fp+306),
    HP(1e108, -0x1.0b0bf8c85bef9p+304),
    HP(1e107, 0x1.87ecd8590680ap+300),
    HP(1e106, -0x1.c9a1430f96ffbp+298),
    HP(1e105, 0x1.f09794b3db339p+294),
    HP(1e104, -0x1.8a712136e13d3p+286),
    HP(1e103, -0x1.3b8db42be7642p+283),
    HP(1e102, 0x1.7a0b6dfb9c0f9p+283),
    HP(1e101, 0x1.2e6f8b2fb00c7p+280),
    HP(1e100, -0x1.4f4d87b3b31f4p+276),
    HP(1e99, 0x1.137a9684eb8d1p+274),
    HP(1e98, 0x1.f2a8a6e45ae8ep+266),
    HP(1e97, -0x1.8d222f071753cp+268),
    HP(1e96, -0x1.ae9d180b58860p+264),
    HP(1e95, -0x1.1761c012273cdp+260),
    HP(1e94, -0x1.bf02cce9d8616p+256),
    HP(1e93, -0x1.7f9ab85d89c08p+254),
    HP(1e92, -0x1.32e22d17a166dp+251),
    HP(1e91, -0x1.c24e8a794debep+248),
    HP(1e90, 0x1.2f8255a450203p+244),
    HP(1e89, 0x1.300ef0e867347p+238),
    HP(1e88, 0x1.d6696361ae3dbp+237),
    HP(1e87, 0x1.78544f8158315p+234),
    HP(1e86, -0x1.b22567fbb2954p+229),
    HP(1e85, -0x1.5b511ffc8eddcp+226),
    HP(1e84, -0x1.12436ccc1c92cp+225),
    HP(1e83, -0x1.d40af5c05b6f3p+220),
    HP(1e82, 0x1.bcc40832ea0d6p+217),
    HP(1e81, 0x1.7eb4d0145d9efp+215),
    HP(1e80, -0x1.08f322e84da10p+204),
    HP(1e79, 0x1.9649c2c37f079p+207),
    HP(1e78, -0x1.52472a5b364e1p+202),
    HP(1e77, 0x1.1249ef0eb713fp+200),
    HP(1e76, -0x1.2be26d2d505e6p+198),
    HP(1e75, 0x1.767e0f0ef2e7ap+195),
    HP(1e74, 0x1.8a634b4b1e3f7p+191),
    HP(1e73, 0x1.bad75756c7317p+186),
    HP(1e72, 0x1.255e44aaf4a37p+185),
    HP(1e71, -0x1.5dcf9221abc73p+181),
    HP(1e70, -0x1.e4a60e815638fp+178),
    HP(1e69, -0x1.83b80b9aab60cp+175),
    HP(1e68, 0x1.93a653d55431fp+171),
    HP(1e67, 0x1.d87aa5ddda397p+166),
    HP(1e66, 0x1.2b4bbac5f871ep+165),
    HP(1e65, 0x1.1517de8c9c728p+159),
    HP(1e64, -0x1.2ac340948e389p+157),
    HP(1e63, -0x1.444e19d505b03p+155),
    HP(1e62, -0x1.3a168fbb3c4d2p+151),
    HP(1e61, 0x1.6b21269d695bdp+148),
    HP(1e60, 0x1.2280ebb121164p+145),
    HP(1e59, 0x1.0401791b6823ap+141),
    HP(1e58, 0x1.9ccdfa7c534fbp+138),
    HP(1e57, -0x1.1c28046956f36p+135),
    HP(1e56, -0x1.b020038778c2bp+132),
    HP(1e55, -0x1.3400169638117p+126),
    HP(1e54, -0x1.d73337b7a4d04p+125),
    HP(1e53, 0x1.051e9b68adfe1p+119),
    HP(1e52, 0x1.a1ca924116635p+115),
    HP(1e51, 0x1.4e3ba83411e91p+112),
    HP(1e50, -0x1.782d3bfacb024p+112),
    HP(1e49, 0x1.a61e066ebb2f8p+108),
    HP(1e48, -0x1.14b4c7a76a405p+105),
    HP(1e47, -0x1.babad90bdd33cp+101),
    HP(1e46, 0x1.bb542c80deb48p+95),
    HP(1e45, 0x1.c5eed14016454p+95),
    HP(1e44, -0x1.c80dbeffee2f0p+92),
    HP(1e43, -0x1.cd24c665f4600p+86),
    HP(1e42, -0x1.29075ae130e00p+85),
    HP(1e41, -0x1.069578d46c000p+79),
    HP(1e40, -0x1.0151182a7c000p+78),
    HP(1e39, 0x1.988becaad0000p+75),
    HP(1e38, 0x1.e826288900000p+70),
    HP(1e37, 0x1.900f436a00000p+68),
    HP(1e36, -0x1.265a307800000p+65),
    HP(1e35, 0x1.5c3c7f4000000p+61),
    HP(1e34, 0x1.e363990000000p+58),
    HP(1e33, 0x1.82b6140000000p+55),
    HP(1e32, -0x1.3107f00000000p+52),
    HP(1e31, 0x1.4b26800000000p+48),
    HP(1e30, -0x1.215c000000000p+44),
    HP(1e29, 0x1.f2a8000000000p+42),
    HP(1e28, 0x1.8440000000000p+38),
    HP(1e27, -0x1.8c00000000000p+33),
    HP(1e26, -0x1.1c00000000000p+32),
    HP(1e25, -0x1.b000000000000p+29),
    HP(1e24, 0x1.0000000000000p+24),
    HP(1e23, 0x1.0000000000000p+23),
    HP(1e22, 0x0.0000000000000p+0),
    HP(1e21, 0x0.0000000000000p+0),
    HP(1e20, 0x0.0000000000000p+0),
    HP(1e19, 0x0.0000000000000p+0),
    HP(1e18, 0x0.0000000000000p+0),
    HP(1e17, 0x0.0000000000000p+0),
    HP(1e16, 0x0.0000000000000p+0),
    HP(1e15, 0x0.0000000000000p+0),
    HP(1e14, 0x0.0000000000000p+0),
    HP(1e13, 0x0.0000000000000p+0),
    HP(1e12, 0x0.0000000000000p+0),
    HP(1e11, 0x0.0000000000000p+0),
    HP(1e10, 0x0.0000000000000p+0),
    HP(1e9, 0x0.0000000000000p+0),
    HP(1e8, 0x0.0000000000000p+0),
    HP(1e7, 0x0.0000000000000p+0),
    HP(1e6, 0x0.0000000000000p+0),
    HP(1e5, 0x0.0000000000000p+0),
    HP(1e4, 0x0.0000000000000p+0),
    HP(1e3, 0x0.0000000000000p+0),
    HP(1e2, 0x0.0000000000000p+0),
    HP(1e1, 0x0.0000000000000p+0),
    HP(1e0, 0x0.0000000000000p+0),
    HP(1e-1, -0x1.9999999999999p-58),
    HP(1e-2, -0x1.eb851eb851eb8p-63),
    HP(1e-3, -0x1.89374bc6a7ef9p-66),
    HP(1e-4, -0x1.6a161e4f765fdp-68),
    HP(1e-5, -0x1.ee78183f91e64p-71),
    HP(1e-6, 0x1.b5a63f9a49c2cp-75),
    HP(1e-7, 0x1.5e1e99483b023p-78),
    HP(1e-8, -0x1.03023df2d4c94p-82),
    HP(1e-9, -0x1.34674bfabb83bp-84),
    HP(1e-10, -0x1.20a5465df8d2bp-88),
    HP(1e-11, 0x1.7f7bc7b4d28a9p-91),
    HP(1e-12, 0x1.97f27f0f6e885p-96),
    HP(1e-13, -0x1.ecd79a5a0df94p-99),
    HP(1e-14, 0x1.ea70909833de7p-107),
    HP(1e-15, -0x1.937831647f5a0p-104),
    HP(1e-16, 0x1.5b4c2ebe68798p-109),
    HP(1e-17, -0x1.db7b2080a3029p-111),
    HP(1e-18, -0x1.7c628066e8cedp-114),
    HP(1e-19, 0x1.a52b31e9e3d06p-119),
    HP(1e-20, 0x1.75447a5d8e535p-121),
    HP(1e-21, 0x1.f769fb7e0b75ep-124),
    HP(1e-22, -0x1.a7566d9cba769p-128),
    HP(1e-23, 0x1.13badb829e078p-131),
    HP(1e-24, 0x1.a96249354b393p-134),
    HP(1e-25, -0x1.5762be11213e0p-138),
    HP(1e-26, -0x1.12b564da80fe6p-141),
    HP(1e-27, -0x1.b788a15d9b30ap-145),
    HP(1e-28, 0x1.06c5e54eb70c4p-148),
    HP(1e-29, 0x1.9f04b7722c09dp-151),
    HP(1e-30, -0x1.e72f6d3e432b5p-154),
    HP(1e-31, -0x1.85bf8a9835bc4p-157),
    HP(1e-32, -0x1.a2cc10f3892d3p-161),
    HP(1e-33, -0x1.4f09a7293a8a9p-164),
    HP(1e-34, 0x1.5a5ead789df78p-167),
    HP(1e-35, -0x1.e1aa86c4e6d2ep-174),
    HP(1e-36, 0x1.696ef285e8eaep-174),
    HP(1e-37, -0x1.4540d794df441p-177),
    HP(1e-38, 0x1.2acb73de9ac64p-181),
    HP(1e-39, 0x1.bbd5f64baf050p-184),
    HP(1e-40, 0x1.631191d6259d9p-187),
    HP(1e-41, -0x1.72524ee484eb4p-194),
    HP(1e-42, -0x1.e3aa0fc74dc8ap-195),
    HP(1e-43, -0x1.8e44064fb8b6ap-197),
    HP(1e-44, 0x1.82c65c4d3edbbp-201),
    HP(1e-45, 0x1.a27ac0f72f8bfp-206),
    HP(1e-46, -0x1.e46a98d3d9f66p-209),
    HP(1e-47, 0x1.afaab8f01e6e1p-212),
    HP(1e-48, 0x1.595560c018580p-215),
    HP(1e-49, 0x1.56eef38009bcdp-217),
    HP(1e-50, -0x1.06d38332f4e12p-223),
    HP(1e-51, -0x1.a4859eb7ee350p-227),
    HP(1e-52, -0x1.506ae55ff1c40p-230),
    HP(1e-53, -0x1.10156113305a6p-231),
    HP(1e-54, -0x1.b355681eb3c3dp-235),
    HP(1e-55, 0x1.eaaa326eb4b42p-241),
    HP(1e-56, -0x1.6888948e87879p-241),
    HP(1e-57, 0x1.45f922c12d2d2p-244),
    HP(1e-58, -0x1.29a4953151516p-248),
    HP(1e-59, -0x1.dc3a884ee8823p-252),
    HP(1e-60, 0x1.b63792f412cb0p-255),
    HP(1e-61, -0x1.d4a0573cbdc3fp-258),
    HP(1e-62, -0x1.76e6ac3097cffp-261),
    HP(1e-63, -0x1.f8b889c079732p-264),
    HP(1e-64, 0x1.a53f2398d747bp-268),
    HP(1e-65, 0x1.754c74a3894fep-270),
    HP(1e-66, 0x1.775b0ed81dcc6p-275),
    HP(1e-67, 0x1.62f139233f1e9p-277),
    HP(1e-68, -0x1.4a7238b09a4dfp-280),
    HP(1e-69, 0x1.227c7218a2b67p-284),
    HP(1e-70, 0x1.b96c1ad4ef863p-291),
    HP(1e-71, 0x1.afabce243f2d1p-290),
    HP(1e-72, 0x1.1912e36d31e1cp-294),
    HP(1e-73, 0x1.40f1c575b1b05p-301),
    HP(1e-74, 0x1.b9b1c6f22b5e6p-301),
    HP(1e-75, 0x1.615b058e89185p-304),
    HP(1e-76, 0x1.e77c04720746ap-307),
    HP(1e-77, 0x1.85fcd05b39055p-310),
    HP(1e-78, 0x1.3290123e9aab2p-319),
    HP(1e-79, 0x1.ea801d30f7783p-323),
    HP(1e-80, 0x1.a5dccd879fc96p-321),
    HP(1e-81, 0x1.517d71394ca11p-324),
    HP(1e-82, 0x1.0dfdf42dd6e74p-327),
    HP(1e-83, -0x1.8336795041c11p-331),
    HP(1e-84, -0x1.35c52dd9ce341p-334),
    HP(1e-85, 0x1.4391503d1c797p-338),
    HP(1e-86, -0x1.e4f9131ac1690p-340),
    HP(1e-87, -0x1.431d09ef37b67p-345),
    HP(1e-88, 0x1.e52795a0501d6p-347),
    HP(1e-89, -0x1.c48d76ff7fd0fp-351),
    HP(1e-90, 0x1.7c76a00334606p-357),
    HP(1e-91, -0x1.4d81dfff5becbp-358),
    HP(1e-92, 0x1.1d96999aa01edp-362),
    HP(1e-93, 0x1.d2b7b85220062p-363),
    HP(1e-94, 0x1.5125f3b699a37p-367),
    HP(1e-95, 0x1.03aca57b853e4p-372),
    HP(1e-96, 0x1.cd88ede5810c7p-373),
    HP(1e-97, -0x1.1d8b502a64b8dp-377),
    HP(1e-98, 0x1.81f6f3114905bp-380),
    HP(1e-99, -0x1.9350296249875p-385),
    HP(1e-100, -0x1.42a68781d46c4p-388),
    HP(1e-101, -0x1.4ddc3633ee91bp-390),
    HP(1e-102, 0x1.5b4fd4a341250p-393),
    HP(1e-103, 0x1.5ee6210535080p-397),
    HP(1e-104, 0x1.e584e7375da00p-400),
    HP(1e-105, 0x1.6f3b0b8bc9001p-404),
    HP(1e-106, 0x1.f295a2d63a667p-407),
    HP(1e-107, -0x1.576fb7608f5aap-415),
    HP(1e-108, -0x1.aac595f8072aep-414),
    HP(1e-109, 0x1.10baece64f769p-419),
    HP(1e-110, -0x1.630dd09ebce84p-420),
    HP(1e-111, -0x1.e8d7da1897203p-423),
    HP(1e-112, 0x1.bea6a30bdaffap-427),
    HP(1e-113, 0x1.310a9e795e65dp-431),
    HP(1e-114, -0x1.1f955a35da3dap-433),
    HP(1e-115, -0x1.cc2229efc395dp-437),
    HP(1e-116, 0x1.4bf226ce4f740p-443),
    HP(1e-117, -0x1.5735f83d234f3p-444),
    HP(1e-118, 0x1.0e100c6afab47p-448),
    HP(1e-119, -0x1.831985bb3bac0p-452),
    HP(1e-120, 0x1.fd852e9d69dccp-455),
    HP(1e-121, 0x1.979dbee454b0ap-458),
    HP(1e-122, -0x1.c35a807177b95p-460),
    HP(1e-123, -0x1.6915338df9611p-463),
    HP(1e-124, 0x1.4588a38e6bb25p-466),
    HP(1e-125, -0x1.762f1c7081f10p-472),
    HP(1e-126, 0x1.4ec360b64c696p-473),
    HP(1e-127, -0x1.1b94320f85bdcp-477),
    HP(1e-128, -0x1.afa9c1a60497dp-480),
    HP(1e-129, 0x1.d9de9847fc535p-483),
    HP(1e-130, -0x1.b81ab96002f08p-486),
    HP(1e-131, 0x1.cc21c3ffed2fdp-492),
    HP(1e-132, 0x1.701b033324264p-495),
    HP(1e-133, -0x1.4ffa98f5c591fp-496),
    HP(1e-134, -0x1.4cc427efa2831p-500),
    HP(1e-135, -0x1.0a3686594ecf4p-503),
    HP(1e-136, -0x1.0573d5bb14ba8p-511),
    HP(1e-137, 0x1.7f746aa07ded5p-511),
    HP(1e-138, -0x1.cd04a22634077p-513),
    HP(1e-139, -0x1.480769d6b9a58p-517),
    HP(1e-140, 0x1.265a89dba3c3ep-521),
    HP(1e-141, -0x1.23dbc8db58180p-523),
    HP(1e-142, -0x1.d2f9415ef359ap-527),
    HP(1e-143, 0x1.bd9efee73d51ep-530),
    HP(1e-144, 0x1.647f32529774bp-533),
    HP(1e-145, 0x1.e9ff5b7545f6fp-536),
    HP(1e-146, -0x1.e0020e88b9b68p-541),
    HP(1e-147, 0x1.b3318df905079p-544),
    HP(1e-148, 0x1.7ae09f3068697p-546),
    HP(1e-149, 0x1.8935309ae7b7cp-551),
    HP(1e-150, -0x1.7c2297a9e74d6p-556),
    HP(1e-151, 0x1.739624089c11dp-556),
    HP(1e-152, -0x1.3d217cc5e98b5p-559),
    HP(1e-153, -0x1.2e9bfad642788p-563),
    HP(1e-154, 0x1.4f066ea92f3f3p-567),
    HP(1e-155, -0x1.1b28e88ae79aep-571),
    HP(1e-156, -0x1.3e105d045ca45p-573),
    HP(1e-157, 0x1.67f2e8c94f7c8p-576),
    HP(1e-158, -0x1.4670df5ef39c6p-579),
    HP(1e-159, 0x1.7060d0d3827d8p-585),
    HP(1e-160, 0x1.26b3da42cecadp-588),
    HP(1e-161, -0x1.23b80f187a154p-590),
    HP(1e-162, 0x1.7d065a52d1889p-593),
    HP(1e-163, 0x1.fd9eaea8a7a07p-596),
    HP(1e-164, 0x1.95cab10dd900bp-600),
    HP(1e-165, -0x1.53ddc96d49973p-605),
    HP(1e-166, -0x1.10c5f515db84ap-606),
    HP(1e-167, -0x1.ad654efc5a107p-614),
    HP(1e-168, -0x1.af11dd8c9e1a6p-613),
    HP(1e-169, -0x1.181c95adc9c3ep-617),
    HP(1e-170, 0x1.730576e9f0603p-621),
    HP(1e-171, 0x1.28d12bee59e68p-624),
    HP(1e-172, -0x1.22df88070f3d6p-626),
    HP(1e-173, -0x1.d165a671b1fbcp-630),
    HP(1e-174, 0x1.2a423d2859b47p-636),
    HP(1e-175, 0x1.dd36c8408f872p-640),
    HP(1e-176, 0x1.7dc56d0072d28p-643),
    HP(1e-177, 0x1.bfc6f14cd8484p-643),
    HP(1e-178, 0x1.6638c10a46a03p-646),
    HP(1e-179, -0x1.ec172fdf1dff5p-651),
    HP(1e-180, -0x1.89ac264c17ff7p-654),
    HP(1e-181, -0x1.6a44dc1e6fffcp-656),
    HP(1e-182, -0x1.21d0b01859996p-659),
    HP(1e-183, -0x1.b0d59ad147abfp-666),
    HP(1e-184, -0x1.c4e22914ed913p-666),
    HP(1e-185, 0x1.7a5892ad42c52p-672),
    HP(1e-186, 0x1.bf6f41de2046ep-672),
    HP(1e-187, -0x1.9d37f40bfe3a2p-678),
    HP(1e-188, 0x1.46f4cf30cd279p-679),
    HP(1e-189, -0x1.60d5c0a5c246bp-682),
    HP(1e-190, -0x1.35df3545a0e26p-687),
    HP(1e-191, -0x1.efcb886f67d09p-691),
    HP(1e-192, -0x1.fcc24e7cae5cep-692),
    HP(1e-193, -0x1.946a172de3c7ep-696),
    HP(1e-194, -0x1.daed16f93f4c6p-701),
    HP(1e-195, -0x1.f895d1650ca8ep-702),
    HP(1e-196, -0x1.8dbc823b47749p-706),
    HP(1e-197, 0x1.6da4c5a8b4f14p-711),
    HP(1e-198, 0x1.e2ba8dee8a96ap-712),
    HP(1e-199, 0x1.3bee92fb55154p-717),
    HP(1e-200, 0x1.f97db7f888220p-721),
    HP(1e-201, 0x1.31e5f1981b3a0p-722),
    HP(1e-202, -0x1.49c34a3fd46ffp-726),
    HP(1e-203, -0x1.07cf6e9976bffp-729),
    HP(1e-204, -0x1.8fe2eb7e2665bp-738),
    HP(1e-205, -0x1.3fe8bc64eb849p-741),
    HP(1e-206, -0x1.a9986fd1d8936p-740),
    HP(1e-207, 0x1.bc296cdf42f83p-742),
    HP(1e-208, -0x1.cfdedc1a30d30p-745),
    HP(1e-209, -0x1.4c97c6904e1e6p-749),
    HP(1e-210, -0x1.0a1305403e7ebp-752),
    HP(1e-211, -0x1.a1a8d10031fefp-755),
    HP(1e-212, 0x1.63beb199499b3p-759),
    HP(1e-213, 0x1.1c988e143ae29p-762),
    HP(1e-214, 0x1.b07a0b43624edp-765),
    HP(1e-215, -0x1.4c0987942f81dp-769),
    HP(1e-216, -0x1.09a139435934ap-772),
    HP(1e-217, -0x1.a14dc769142a2p-775),
    HP(1e-218, -0x1.02160bdb53769p-779),
    HP(1e-219, -0x1.9cf012f8858a9p-783),
    HP(1e-220, 0x1.3cffc34b2177bp-788),
    HP(1e-221, -0x1.1acce51525d01p-790),
    HP(1e-222, -0x1.3deb8ed542533p-792),
    HP(1e-223, 0x1.36871b7795e13p-796),
    HP(1e-224, -0x1.425b0740a9cadp-800),
    HP(1e-225, 0x1.18a8637fbc154p-802),
    HP(1e-226, 0x1.ad5382cc96776p-805),
    HP(1e-227, 0x1.e21f37adbd8bdp-809),
    HP(1e-228, -0x1.c967a6ea03ed0p-813),
    HP(1e-229, -0x1.83c30f90ce5edp-815),
    HP(1e-230, -0x1.9f9e7f4e16fe1p-819),
    HP(1e-231, 0x1.346b356c83394p-824),
    HP(1e-232, -0x1.1e3b843afeb5ep-826),
    HP(1e-233, 0x1.8169fc9d9aa1ap-829),
    HP(1e-234, 0x1.3454ca17aee7bp-832),
    HP(1e-235, 0x1.ed54768c4b0c6p-836),
    HP(1e-236, -0x1.a8893ac2f7294p-839),
    HP(1e-237, 0x1.17e27729b5e24p-844),
    HP(1e-238, 0x1.bfd0bea92303ap-848),
    HP(1e-239, -0x1.6cd18688afb2dp-848),
    HP(1e-240, 0x1.d6fb1e4a9a908p-853),
    HP(1e-241, 0x1.78c8e5087ba6dp-856),
    HP(1e-242, 0x1.2d6d8406c9524p-859),
    HP(1e-243, 0x1.22bce691d541ap-865),
    HP(1e-244, 0x1.b6ac7d74fbb9cp-865),
    HP(1e-245, 0x1.5ef0645d962e3p-868),
    HP(1e-246, 0x1.64b3d3c8f049fp-872),
    HP(1e-247, -0x1.f0f3c0b032469p-877),
    HP(1e-248, 0x1.a5a365d971612p-880),
    HP(1e-249, -0x1.bdbea40f6c3f8p-882),
    HP(1e-250, -0x1.6498833f89cc7p-885),
    HP(1e-251, -0x1.41e80a64ec27cp-890),
    HP(1e-252, 0x1.e5a32f0ad4bcep-892),
    HP(1e-253, -0x1.aeb0a72a89027p-895),
    HP(1e-254, 0x1.daa5e0aac5979p-898),
    HP(1e-255, -0x1.de1b2aa952051p-905),
    HP(1e-256, 0x1.39fa911155fefp-906),
    HP(1e-257, 0x1.f65db4e88997fp-910),
    HP(1e-258, 0x1.95bf1529d0a33p-912),
    HP(1e-259, -0x1.ee9a557825e3dp-915),
    HP(1e-260, 0x1.b56f773fc3603p-919),
    HP(1e-261, 0x1.224bf1ff9f006p-923),
    HP(1e-262, -0x1.62b9b0009b329p-927),
    HP(1e-263, -0x1.1bc7c0007c287p-930),
    HP(1e-264, -0x1.c60c66672d0d8p-934),
    HP(1e-265, 0x1.c7f6147a425b9p-937),
    HP(1e-266, 0x1.6cc4dd2e9b7c7p-940),
    HP(1e-267, 0x1.23d0b0f215fd2p-943),
    HP(1e-268, 0x1.4186ad2da2654p-945),
    HP(1e-269, 0x1.01388a8ae8510p-948),
    HP(1e-270, -0x1.97a588bb5917fp-952),
    HP(1e-271, 0x1.20485f6a1f200p-955),
    HP(1e-272, 0x1.b36d1921b2800p-958),
    HP(1e-273, -0x1.d6dbebe50acccp-961),
    HP(1e-274, 0x1.0ea0202b21eb8p-965),
    HP(1e-275, 0x1.a54ce688e7efap-968),
    HP(1e-276, -0x1.e228e12c13404p-971),
    HP(1e-277, 0x1.f916c90c8f323p-976),
    HP(1e-278, 0x1.96d5ea0506141p-978),
    HP(1e-279, -0x1.20ee77fbfb231p-981),
    HP(1e-280, 0x1.64e8d9a007c7cp-985),
    HP(1e-281, -0x1.f04a14664d809p-990),
    HP(1e-282, -0x1.8d081051d79a1p-993),
    HP(1e-283, 0x1.c7965fdf435bfp-995),
    HP(1e-284, -0x1.f3dc33679439ap-999),
    HP(1e-285, -0x1.94be7af63b4a4p-1001),
    HP(1e-286, -0x1.baca5e56c5439p-1005),
    HP(1e-287, -0x1.2add63be086c3p-1009),
    HP(1e-288, -0x1.44588e4c035e7p-1011),
    HP(1e-289, -0x1.b569f519af297p-1017),
    HP(1e-290, -0x1.f115310523084p-1018),
    HP(1e-291, 0x1.b177b191618c5p-1022),
];

private char[] errol1(const double value,
                      return ref char[512] digits,
                      out int exponent) @nogc nothrow pure @safe
{
    // Phase 1: Exponent Estimation
    exponent = cast(int) (frexp(value) * 0.30103);
    auto e = cast(size_t) (exponent + 307);

    if (e >= powersOf10.length)
    {
        exponent = powersOf10.length - 308;
        e = powersOf10.length - 1;
    }
    HP t = powersOf10[e];

    HP scaledInput = t * value;

    while (scaledInput.base > 10.0
        || (scaledInput.base == 10.0 && scaledInput.offset >= 0.0))
    {
        scaledInput.divideBy10();
        ++exponent;
        t.base /= 10.0;
    }
    while (scaledInput.base < 1.0
        || (scaledInput.base == 1.0 && scaledInput.offset < 0.0))
    {
        scaledInput.multiplyBy10();
        --exponent;
        t.base *= 10.0;
    }

    // Phase 2: Boundary Computation
    const double factor = t.base / (2.0 + epsilon);

    // Upper narrow boundary
    FloatBits!double neighbour = { value };
    --neighbour.integral;
    auto nMinus = HP(scaledInput.base, scaledInput.offset
                                     + (neighbour.floating - value) * factor);
    nMinus.normalize();

    // Lower narrow boundary
    neighbour.floating = value;
    ++neighbour.integral;
    auto nPlus = HP(scaledInput.base, scaledInput.offset
                                    + (neighbour.floating - value) * factor);
    nPlus.normalize();

    // Phase 3: Exponent Rectification
    while (nPlus.base > 10.0 || (nPlus.base == 10.0 && nPlus.offset >= 0.0))
    {
        nMinus.divideBy10();
        nPlus.divideBy10();
        ++exponent;
    }
    while (nPlus.base < 1.0 || (nPlus.base == 1.0 && nPlus.offset < 0.0))
    {
        nMinus.multiplyBy10();
        nPlus.multiplyBy10();
        --exponent;
    }

    // get_digits_hp
    byte dMinus, dPlus;

    size_t i;
    do
    {
        dMinus = cast(byte) nMinus.base;
        dPlus = cast(byte) nPlus.base;

        if (nMinus.base == dMinus && nMinus.offset < 0.0)
        {
            --dMinus;
        }
        if (nPlus.base == dPlus && nPlus.offset < 0.0)
        {
            --dPlus;
        }

        if (dMinus != dPlus)
        {
            digits[i] = cast(char) ('0' + cast(ubyte) ((dPlus + dMinus) / 2.0 + 0.5));
            break;
        }
        else
        {
            digits[i] = cast(char) ('0' + cast(ubyte) dPlus);
        }
        ++i;

        nMinus.base -= dMinus;
        nPlus.base -= dPlus;
        nPlus.multiplyBy10();
        nMinus.multiplyBy10();
    }
    while (nPlus.base != 0.0 || nPlus.offset != 0.0);

    return digits[0 .. i + 1];
}

@nogc nothrow pure @safe unittest
{
	char[512] buf;
    int e;

    assert(errol1(18.51234334, buf, e) == "1851234334");
    assert(e == 2);

    assert(errol1(0.23432e304, buf, e) == "23432");
    assert(e == 304);
}

/*
 * Given a float value, returns the significant bits, and the position of the
 * decimal point in $(D_PARAM exponent). +/-Inf and NaN are specified by
 * special values returned in the $(D_PARAM exponent). Sing bit is set in
 * $(D_PARAM sign).
 */
private const(char)[] real2String(double value,
                                  ref char[512] buffer,
                                  out int exponent,
                                  out bool sign) @nogc nothrow pure @trusted
{
    const FloatBits!double bits = { value };

    exponent = (bits.integral >> 52) & 0x7ff;
    sign = signBit(value);
    if (sign)
    {
        value = -value;
    }

    if (exponent == 0x7ff) // Is NaN or Inf?
    {
        exponent = special;
        return (bits.integral & ((1UL << 52) - 1)) != 0 ? "NaN" : "Inf";
    }

    if (exponent == 0 && (bits.integral << 1) == 0) // Is zero?
    {
        exponent = 1;
        buffer[0] = '0';
        return buffer[0 .. 1];
    }

    if (value == double.max)
    {
        copy("17976931348623157", buffer);
        exponent = 309;
        return buffer;
    }

    return errol1(value, buffer, exponent);
}

private void formatReal(T)(ref T arg, ref String result)
if (isFloatingPoint!T)
{
    char[512] buffer; // Big enough for e+308 or e-307.
    char[8] tail = 0;
    char[] bufferSlice = buffer[64 .. $];
    uint precision = 6;
    bool negative;
    int decimalPoint;

    // Read the double into a string.
    auto realString = real2String(arg, buffer, decimalPoint, negative);
    auto length = cast(uint) realString.length;

    // Clamp the precision and delete extra zeros after clamp.
    uint n = precision;
    if (length > precision)
    {
        length = precision;
    }
    while ((length > 1) && (precision != 0) && (realString[length - 1] == '0'))
    {
        --precision;
        --length;
    }

    if (negative)
    {
        result.insertBack('-');
    }
    if (decimalPoint == special)
    {
        result.insertBack(realString);
        return;
    }

    // Should we use sceintific notation?
    if ((decimalPoint <= -4) || (decimalPoint > cast(int) n))
    {
        if (precision > length)
        {
            precision = length - 1;
        }
        else if (precision > 0)
        {
           // When using scientific notation, there is one digit before the
           // decimal.
           --precision;
        }

        // Handle leading chars.
        bufferSlice.front = realString[0];
        bufferSlice.popFront();

        if (precision != 0)
        {
            bufferSlice.front = period;
            bufferSlice.popFront();
        }

        // Handle after decimal.
        if ((length - 1) > precision)
        {
            length = precision + 1;
        }
        realString[1 .. length].copy(bufferSlice);
        bufferSlice.popFrontExactly(length - 1);

        // Dump the exponent.
        tail[1] = 'e';
        --decimalPoint;
        if (decimalPoint < 0)
        {
            tail[2] = '-';
            decimalPoint = -decimalPoint;
        }
        else
        {
            tail[2] = '+';
        }

        n = decimalPoint >= 100 ? 5 : 4;

        tail[0] = cast(char) n;
        while (true)
        {
            tail[n] = '0' + decimalPoint % 10;
            if (n <= 3)
            {
                break;
            }
            --n;
            decimalPoint /= 10;
        }
    }
    else
    {
        if (decimalPoint > 0)
        {
            precision = decimalPoint < (cast(int) length)
                      ? length - decimalPoint
                      : 0;
        }
        else
        {
            precision = -decimalPoint
                      + (precision > length ? length : precision);
        }

        // Handle the three decimal varieties.
        if (decimalPoint <= 0)
        {
            // Handle 0.000*000xxxx.
            bufferSlice.front = '0';
            bufferSlice.popFront();

            if (precision != 0)
            {
                bufferSlice.front = period;
                bufferSlice.popFront();
            }
            n = -decimalPoint;
            if (n > precision)
            {
                n = precision;
            }

            fill!'0'(bufferSlice[0 .. n]);
            bufferSlice.popFrontExactly(n);

            if ((length + n) > precision)
            {
                length = precision - n;
            }

            realString[0 .. length].copy(bufferSlice);
            bufferSlice.popFrontExactly(length);
        }
        else if (cast(uint) decimalPoint >= length)
        {
            // Handle xxxx000*000.0.
            n = 0;
            do
            {
                bufferSlice.front = realString[n];
                bufferSlice.popFront();
                ++n;
            }
            while (n < length);
            if (n < cast(uint) decimalPoint)
            {
                n = decimalPoint - n;

                fill!'0'(bufferSlice[0 .. n]);
                bufferSlice.popFrontExactly(n);
            }
            if (precision != 0)
            {
                bufferSlice.front = period;
                bufferSlice.popFront();
            }
        }
        else
        {
            // Handle xxxxx.xxxx000*000.
            n = 0;
            do
            {
                bufferSlice.front = realString[n];
                bufferSlice.popFront();
                ++n;
            }
            while (n < cast(uint) decimalPoint);

            if (precision > 0)
            {
                bufferSlice.front = period;
                bufferSlice.popFront();
            }
            if ((length - decimalPoint) > precision)
            {
                length = precision + decimalPoint;
            }

            realString[n .. length].copy(bufferSlice);
            bufferSlice.popFrontExactly(length - n);
        }
    }

    // Get the length that we've copied.
    length = cast(uint) (buffer.length - bufferSlice.length);

    result.insertBack(buffer[64 .. length]); // Number.
    result.insertBack(tail[1 .. tail[0] + 1]); // Tail.
}

private void formatStruct(T)(ref T arg, ref String result)
if (is(T == struct))
{
    template pred(alias f)
    {
        static if (f == "this")
        {
            // Exclude context pointer from nested structs.
            enum bool pred = false;
        }
        else
        {
            enum bool pred = !isSomeFunction!(__traits(getMember, arg, f));
        }
    }
    alias fields = Filter!(pred, __traits(allMembers, T));

    result.insertBack(T.stringof);
    result.insertBack('(');
    static if (fields.length > 0)
    {
        printToString!"{}"(result, __traits(getMember, arg, fields[0]));
        foreach (field; fields[1 .. $])
        {
            result.insertBack(", ");
            printToString!"{}"(result, __traits(getMember, arg, field));
        }
    }
    result.insertBack(')');
}

private void formatRange(T)(ref T arg, ref String result)
if (isInputRange!T && !isInfinite!T)
{
    result.insertBack('[');
    if (!arg.empty)
    {
        printToString!"{}"(result, arg.front);
        arg.popFront();
    }
    foreach (e; arg)
    {
        result.insertBack(", ");
        printToString!"{}"(result, e);
    }
    result.insertBack(']');
}

private ref String printToString(string fmt, Args...)(return ref String result,
                                                      auto ref Args args)
{
    alias Arg = Args[0];

    static if (is(Unqual!Arg == typeof(null))) // null
    {
        result.insertBack("null");
    }
    else static if (is(Unqual!Arg == bool)) // Boolean
    {
        result.insertBack(args[0] ? "true" : "false");
    }
    else static if (is(Arg == enum)) // Enum
    {
        foreach (m; __traits(allMembers, Arg))
        {
            if (args[0] == __traits(getMember, Arg, m))
            {
                result.insertBack(m);
            }
        }
    }
    else static if (isSomeChar!Arg || isSomeString!Arg) // String or char
    {
        result.insertBack(args[0]);
    }
    else static if (isInputRange!Arg
                 && !isInfinite!Arg
                 && isSomeChar!(ElementType!Arg)) // Stringish range
    {
        result.insertBack(args[0]);
    }
    else static if (isInputRange!Arg && !isInfinite!Arg)
    {
        formatRange(args[0], result);
    }
    else static if (is(Unqual!(typeof(args[0].stringify())) == String))
    {
        static if (is(Arg == class) || is(Arg == interface))
        {
            if (args[0] is null)
            {
                result.insertBack("null");
            }
            else
            {
                result.insertBack(args[0].stringify()[]);
            }
        }
        else
        {
            result.insertBack(args[0].stringify()[]);
        }
    }
    else static if (is(Arg == class))
    {
        result.insertBack(args[0] is null ? "null" : args[0].toString());
    }
    else static if (is(Arg == interface))
    {
        result.insertBack(Arg.classinfo.name);
    }
    else static if (is(Arg == struct))
    {
        formatStruct(args[0], result);
    }
    else static if (is(Arg == union))
    {
        result.insertBack(Arg.stringof);
    }
    else static if (isFloatingPoint!Arg) // Float
    {
        formatReal(args[0], result);
    }
    else static if (isPointer!Arg) // Pointer
    {
        char[size_t.sizeof * 2] buffer;
        size_t position = buffer.length;
        auto address = cast(size_t) args[0];

        do // Write at least "0" if the pointer is null.
        {
            buffer[--position] = lowerHexDigits[cast(size_t) (address & 15)];
            address >>= 4;
        }
        while (address != 0);

        result.insertBack("0x");
        result.insertBack(buffer[position .. $]);
    }
    else static if (isIntegral!Arg) // Integer
    {
        char[21] buffer;
        result.insertBack(integral2String(args[0], buffer));
    }
    else
    {
        static assert(false,
                      "Formatting type " ~ Arg.stringof ~ " is not supported");
    }

    return result;
}

package(tanya) String format(string fmt, Args...)(auto ref Args args)
{
    String formatted;
    return printToString!fmt(formatted, args);
}

// Enum.
@nogc nothrow pure @safe unittest
{
    enum E1 : int
    {
        one,
        two,
    }
    assert(format!"{}"(E1.one) == "one");

    const E1 e1;
    assert(format!"{}"(e1) == "one");
}

// One argument tests.
@nogc pure @safe unittest
{
    // Modifiers.
    assert(format!"{}"(8.5) == "8.5");
    assert(format!"{}"(8.6) == "8.6");
    assert(format!"{}"(1000) == "1000");
    assert(format!"{}"(1) == "1");
    assert(format!"{}"(10.25) == "10.25");
    assert(format!"{}"(1) == "1");
    assert(format!"{}"(0.01) == "0.01");

    // String printing.
    assert(format!"{}"("Some weired string") == "Some weired string");
    assert(format!"{}"(cast(string) null) == "");
    assert(format!"{}"('c') == "c");

    // Integer.
    assert(format!"{}"(8) == "8");
    assert(format!"{}"(8) == "8");
    assert(format!"{}"(-8) == "-8");
    assert(format!"{}"(-8L) == "-8");
    assert(format!"{}"(8) == "8");
    assert(format!"{}"(100000001) == "100000001");
    assert(format!"{}"(99999999L) == "99999999");
    assert(format!"{}"(10) == "10");
    assert(format!"{}"(10L) == "10");

    // Floating point.
    assert(format!"{}"(0.1234) == "0.1234");
    assert(format!"{}"(0.3) == "0.3");
    assert(format!"{}"(0.333333333333) == "0.333333");
    assert(format!"{}"(38234.1234) == "38234.1");
    assert(format!"{}"(-0.3) == "-0.3");
    assert(format!"{}"(0.000000000000000006) == "6e-18");
    assert(format!"{}"(0.0) == "0");
    assert(format!"{}"(double.init) == "NaN");
    assert(format!"{}"(-double.init) == "-NaN");
    assert(format!"{}"(double.infinity) == "Inf");
    assert(format!"{}"(-double.infinity) == "-Inf");
    assert(format!"{}"(0.000000000000000000000000003) == "3e-27");
    assert(format!"{}"(0.23432e304) == "2.3432e+303");
    assert(format!"{}"(-0.23432e8) == "-2.3432e+07");
    assert(format!"{}"(1e-307) == "1e-307");
    assert(format!"{}"(1e+8) == "1e+08");
    assert(format!"{}"(111234.1) == "111234");
    assert(format!"{}"(0.999) == "0.999");
    assert(format!"{}"(0x1p-16382L) == "0");
    assert(format!"{}"(1e+3) == "1000");
    assert(format!"{}"(38234.1234) == "38234.1");

    // typeof(null).
    assert(format!"{}"(null) == "null");

    // Boolean.
    assert(format!"{}"(true) == "true");
    assert(format!"{}"(false) == "false");
}

// Unsafe tests with pointers.
@nogc pure @system unittest
{
    // Pointer convesions
    assert(format!"{}"(cast(void*) 1) == "0x1");
    assert(format!"{}"(cast(void*) 20) == "0x14");
    assert(format!"{}"(cast(void*) null) == "0x0");
}

// Structs.
@nogc pure @safe unittest
{
    static struct WithoutStringify1
    {
        int a;
        void func()
        {
        }
    }
    assert(format!"{}"(WithoutStringify1(6)) == "WithoutStringify1(6)");

    static struct WithoutStringify2
    {
    }
    assert(format!"{}"(WithoutStringify2()) == "WithoutStringify2()");

    static struct WithoutStringify3
    {
        int a = -2;
        int b = 8;
    }
    assert(format!"{}"(WithoutStringify3()) == "WithoutStringify3(-2, 8)");

    struct Nested
    {
        int i;

        void func()
        {
        }
    }
    assert(format!"{}"(Nested()) == "Nested(0)");

    static struct WithStringify
    {
        String stringify() const @nogc nothrow pure @safe
        {
            return String("stringify method");
        }
    }
    assert(format!"{}"(WithStringify()) == "stringify method");
}

// Aggregate types.
@system unittest // Object.toString has no attributes.
{
    import tanya.memory;
    import tanya.memory.smartref;

    interface I
    {
    }
    class A : I
    {
    }
    auto instance = defaultAllocator.unique!A();
    assert(format!"{}"(instance.get()) == instance.get().toString());
    assert(format!"{}"(cast(I) instance.get()) == I.classinfo.name);
    assert(format!"{}"(cast(A) null) == "null");

    class B
    {
        String stringify() @nogc nothrow pure @safe
        {
            return String("Class B");
        }
    }
    assert(format!"{}"(cast(B) null) == "null");
}

// Unions.
unittest
{
    union U
    {
        int i;
        char c;
    }
    assert(format!"{}"(U(2)) == "U");
}

// Ranges.
@nogc pure @safe unittest
{
    static struct Stringish
    {
        private string content = "Some content";

        immutable(char) front() const @nogc nothrow pure @safe
        {
            return this.content[0];
        }

        void popFront() @nogc nothrow pure @safe
        {
            this.content = this.content[1 .. $];
        }

        bool empty() const @nogc nothrow pure @safe
        {
            return this.content.length == 0;
        }
    }
    assert(format!"{}"(Stringish()) == "Some content");

    static struct Intish
    {
        private int front_ = 3;

        int front() const @nogc nothrow pure @safe
        {
            return this.front_;
        }

        void popFront() @nogc nothrow pure @safe
        {
            --this.front_;
        }

        bool empty() const @nogc nothrow pure @safe
        {
            return this.front == 0;
        }
    }
    assert(format!"{}"(Intish()) == "[3, 2, 1]");
}

// Typeid.
nothrow pure @safe unittest
{
    assert(format!"{}"(typeid(int[])) == "int[]");

    class C
    {
    }
    assert(format!"{}"(typeid(C)) == typeid(C).toString());
}

private struct FormatSpec
{
}

// Returns the position of `tag` in `fmt`. If `tag` can't be found, returns the
// length of  `fmt`.
private size_t specPosition(string fmt, char tag)()
{
    foreach (i, c; fmt)
    {
        if (c == tag)
        {
            return i;
        }
    }
    return fmt.length;
}

private template ParseFmt(string fmt, size_t pos = 0)
{
    static if (fmt.length == 0)
    {
        alias ParseFmt = AliasSeq!();
    }
    else static if (fmt[0] == '{')
    {
        static if (fmt.length > 1 && fmt[1] == '{')
        {
            enum size_t pos = specPosition!(fmt[2 .. $], '{') + 2;
            alias ParseFmt = AliasSeq!(fmt[1 .. pos],
                                       ParseFmt!(fmt[pos .. $], pos));
        }
        else
        {
            enum size_t pos = specPosition!(fmt[1 .. $], '}') + 1;
            static if (pos < fmt.length)
            {
                alias ParseFmt = AliasSeq!(FormatSpec(),
                                           ParseFmt!(fmt[pos + 1 .. $], pos + 1));
            }
            else
            {
                static assert(false, "Enclosing '}' is missing");
            }
        }
    }
    else
    {
        enum size_t pos = specPosition!(fmt, '{');
        alias ParseFmt = AliasSeq!(fmt[0 .. pos],
                                   ParseFmt!(fmt[pos .. $], pos));
    }
}

@nogc nothrow pure @safe unittest
{
    static assert(ParseFmt!"".length == 0);

    static assert(ParseFmt!"asdf".length == 1);
    static assert(ParseFmt!"asdf"[0] == "asdf");

    static assert(ParseFmt!"{}".length == 1);
}
