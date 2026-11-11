(
// define Newton solver routine
var f,df;
~newtonSolve = {
	|f, df, x0, rtol = 1e-5, atol = 1e-8, maxIter = 30|
	var x = x0.asFloat;
	var dx = inf;
	var iter=0;
	while { (dx.abs > (atol + (rtol * x.abs))) && (iter < maxIter) }{
		dx = f.(x).neg / df.(x);
		x = x + dx;
		iter = iter + 1;
	};
	if( iter == maxIter) {
		"Warning: exceeded max iterations: (" ++ maxIter.asString ++")".warn;
	};
	x
};

)

(
s.waitForBoot({
	var n = 256;
	var eccs = Array.interpolation(20,0.0,0.98);

	~meanAnomToEccentricAnom = {
		|e,meanAnom|
		var f,df;
		f = {|u| meanAnom - u + (e * sin(u))};
		df = {|u| -1.0 + (e * cos(u))};
		/*RootFinder.findRoot(f,df,meanAnom).at(0);*/
		~newtonSolve.(f,df,meanAnom);
	};

	~radialVelocity =
	{
		| meanAnom, e, omega |
		var u, esq, sinw, cosw,cosu,sinu, num, denom;
		u = ~meanAnomToEccentricAnom.(e,meanAnom);
		cosu = cos(u);
		sinu = sin(u);
		sinw = sin(omega);
		cosw = cos(omega);
		esq = e*e;
		num = ((1-esq).sqrt * cosu * cosw) - (sinu * sinw);
		denom = 1 - (e * cosu);
		num / denom;
	};
	Buffer.freeAll;
	~bcos = Buffer.allocConsecutive(eccs.size,s,2*n);
	~bsin = Buffer.allocConsecutive(eccs.size,s,2*n);
	eccs.do({
		|e, i|
		var rv, rvwt;

		//cosine piece
		rv = Array.interpolation(n,-pi,pi)
		.collect { |m| ~radialVelocity.(m,e,0.0) };
		rv = rv - rv.mean; // ensure zero mean
		rvwt = Signal.newFrom(rv).asWavetable;
		~bcos[i].loadCollection(rvwt);

		// sine piece
		rv = Array.interpolation(n,-pi,pi)
		.collect { |m| ~radialVelocity.(m,e,pi * 0.5) };
		rv = rv - rv.mean; // ensure zero mean
		rvwt = Signal.newFrom(rv).asWavetable;
		~bsin[i].loadCollection(rvwt);
	});
	s.sync; // wait for buffers to be loaded
	"rv signal buffers filled".postln;
	// add synthdef
	SynthDef(
		\rvsignal,
		{
			var bufnum1,bufnum2,freqnoise,snd,omega,sin_sig,cos_sig,env;
			env = Env.asr(
				\atk.kr(0.3),
				(\amp.kr(-10)).dbamp,
				\rel.kr(1),
				\crv.kr((-4))
			);
			env = EnvGen.kr(env,\gate.kr(1),doneAction: Done.freeSelf);
			bufnum1 = \ecc.kr(0).clip(0,0.98).linlin(0,0.98,0,19) + ~bcos[0].bufnum;
			bufnum2 = \ecc.kr(0).clip(0,0.98).linlin(0,0.98,0,18.99) + ~bsin[0].bufnum;
			freqnoise = LFNoise1.kr(5!2).bipolar(\detune.kr(0)).midiratio;
			cos_sig = VOsc.ar(bufnum1,\freq.kr(200) * freqnoise);
			sin_sig = VOsc.ar(bufnum2,\freq.kr(200) * freqnoise);
			omega = \omega.kr(0);
			snd = (omega.cos * cos_sig) + (omega.sin * sin_sig);
			snd = snd * env;
			Out.ar(\out.kr(0),snd);
	}).add;
})
)


(
~fAnalyzer = FreqScope.new(); // frequency analyzer
~steth = s.scope; // stethescope
~steth.cycle=5;
s.newBusAllocators;
~eccCtl = Bus.control(s,1); // control bus for orbital eccentricity
~omegaCtl = Bus.control(s,1); // control bus for argument of peri
// set initial values
~eccCtl.set(0.0);
~omegaCtl.set(pi/2);

fork {
	s.sync;
	// instantiate synth
	x = Synth(\rvsignal,
		[
			ecc: ~eccCtl.asMap,// orbtial eccentricity
			omega: ~omegaCtl.asMap, // argument of pericenter
			\freq:150, // orbital frequency

			// midi ratio value specifying noise level in frequency
			// -- gives nice stereo chorus effect
			\detune: 0.1
		]
	);
	3.wait;

	// modulate eccentricity sinusoidally
	z = {
		var modHz = (1/5);
		var eMax = 0.8;
		Out.kr(
			bus: ~eccCtl,
			channelsArray: SinOsc.kr(modHz).unipolar(eMax)
		);
	}.play;
	10.wait;
	x.release;
	z.free;
}
)
