// Pure wavetable generator plus the original realtime-buffer convenience API.
(
~makeRVTables = { |n = 128, nEcc = 20|
    var eccs, radialVelocity;
    eccs = Array.interpolation(nEcc, 0.0, 0.98);
    radialVelocity = { |meanAnom, e, omega|
        var u = meanAnom, step;
        // Newton iteration for Kepler's equation; no RootFinder quark required.
        30.do {
            step = (u - (e * u.sin) - meanAnom) / (1 - (e * u.cos));
            u = u - step;
        };
        (((1 - e.squared).sqrt * u.cos * omega.cos)
            - (u.sin * omega.sin)) / (1 - (e * u.cos));
    };
    [0.0, pi * 0.5].collect { |omega|
        eccs.collect { |e|
            var rv;
            // Periodic samples omit the duplicate endpoint.
            rv = Array.fill(n, { |i|
                radialVelocity.(-pi + (2pi * i / n), e, omega)
            });
            Signal.newFrom(rv - rv.mean).asWavetable;
        };
    };
};

~loadRVBuffers = { |n = 128, nEcc = 20|
    var tables = ~makeRVTables.(n, nEcc);
    tables.collect { |bank|
        var buffers = Buffer.allocConsecutive(nEcc, s, 2 * n);
        bank.do { |table, i| buffers[i].loadCollection(table) };
        buffers;
    };
};
)
