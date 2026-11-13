

s.boot;

(
// Note: make sure CSV file is in the same folder as this file!
~readSystemAndPeriodsFile = {
	| planetFile =  "transit_multi_orbital_periods_with_systems.csv"|
	var finame = thisProcess.nowExecutingPath.dirname +/+ planetFile;
	var dataList,d;
	// read in data from CSV
	dataList = CSVFileReader.read(
		path: finame,
		skipEmptyLines: true,
		skipBlanks: true

	)
	.postcs;
	d = Dictionary();
	// convert strings to floats
	dataList.do {
		|systemLine|
		d.put(
			systemLine[0],
			systemLine[1..].collect{
				|period|
				period.asFloat;
			};
		);
		};
	d;
};

~readPeriodsFile = {
	| finame = "/Users/hadden/Presentations/2026_06_DDA/transit_multi_orbital_periods.csv" |
	var periodsList;
	// read in data from CSV
	periodsList = CSVFileReader.read(
		path: finame,
		skipEmptyLines: true,
		skipBlanks: true

	)
	.postcs;

	// convert strings to floats
	periodsList = periodsList.collect {
		|sysList|
		sysList.collect{
			|period|
			period.asFloat;
		};
	};
};

x = ~readPeriodsFile.();
~freqs = x.collect { |l| l.collect{|p| 1/p}};
d = ~readSystemAndPeriodsFile.();

~freqsToPoints = {
	|arr|
	(arr.size -2).collect({ |i| [arr[i] / arr[i+1], arr[i+2] / arr[i+1]]});
};
)

(
SynthDef(\playSine,
	{
		var snd,env;
		env = Env.linen(\atk.kr(0.3),\sus.kr(1),\rel.kr(1),\amp.kr(0.2)).kr(Done.freeSelf);
		snd =SinOsc.ar(\freq.kr(400)) * env ! 2;
		Out.ar(\out.kr(0),snd);
	}
).add;

s.meter;
)



(
var s = Server.default;
var win, view;
var points = []; //[[0.2, 0.3], [0.6, 0.8], [0.8, 0.4]];
var sysName = "";
var new_points = [];
var xmin,xmax,ymin,ymax,coordtr;
var dur = 2;
var fnt = Font("Helvetica",20);
var windowSize = 1.0;
xmin = 7/6;
xmax = 2.51;
ymin = 1/2.51;
ymax = 6/7;
coordtr = {|x,y,plot|
	var p = [x.linlin(xmin,xmax,0,1),y.linlin(ymin,ymax,0,1)];
	var xpl = plot.left + (p[0] * plot.width);
	var ypl = plot.bottom - (p[1] * plot.height);
	xpl@ypl;
};
win = Window("XY plot", Rect(100, 100, windowSize*700, windowSize*400)).front;
view = UserView(win, Rect(0, 0, windowSize*700, windowSize*400))
.background_(Color.white)
.drawFunc_({
    var b = view.bounds;
    var left = 60, bottom = 50, top = 20, right = 20;
    var plot = Rect(left, top, b.width-left-right, b.height-top-bottom);

    Pen.color_(Color.black);
    Pen.line(plot.leftBottom, plot.rightBottom);
    Pen.line(plot.leftBottom, plot.leftTop);
    Pen.stroke;
	(2..6).do{
		| k |
		Pen.line(
			coordtr.(k/(k-1),ymin,plot),
			coordtr.(k/(k-1),ymax,plot)
		);
		Pen.line(
			coordtr.(xmin,(k-1)/k,plot),
			coordtr.(xmax,(k-1)/k,plot)
		);
	};
	Pen.stroke;

	"P2/P1".drawAtPoint(Point(plot.center.x, b.height - 25), fnt, Color.black);
	"P2/P3".drawAtPoint(Point(10, plot.center.y), fnt, Color.black);
	sysName.drawAtPoint(Point(plot.center.x-50,20),Font("Helvetica", 24), Color.red);

	"4:3".drawAtPoint(coordtr.(4/3+0.025,1/2.1,plot),fnt, Color.black);
	"3:2".drawAtPoint(coordtr.(3/2+0.025,1/2.1,plot),fnt, Color.black);
	"2:1".drawAtPoint(coordtr.(2/1+0.025,1/2.1,plot), fnt, Color.black);

	"3:4".drawAtPoint(coordtr.(xmax - 0.1,3/4+0.025,plot), fnt, Color.black);
	"2:3".drawAtPoint(coordtr.(xmax - 0.1,2/3+0.025,plot), fnt, Color.black);
	"1:2".drawAtPoint(coordtr.(xmax - 0.1,1/2+0.025,plot), fnt, Color.black);

    Pen.color_(Color.black);  // use this for filled ovals

	points.do { |p|
		var x = plot.left + (p[0] * plot.width);
		var y = plot.bottom - (p[1] * plot.height);
		Pen.fillOval(Rect.aboutPoint(Point(x, y), 5, 5));
	};

	Pen.color_(Color.red);  // use this for filled ovals
	new_points.do { |p|
		var x = plot.left + (p[0] * plot.width);
		var y = plot.bottom - (p[1] * plot.height);
		Pen.fillOval(Rect.aboutPoint(Point(x, y), 5, 5));
	};
	Pen.stroke;

});
Routine({
	d.keysValuesDo {
		| key,value |
		var flist = 1/value;
		var fqs = flist*4000;
		var len = fqs.size;
		var step = dur / 3 / len;
		var pointPositions = ~freqsToPoints.(flist);
		sysName = key;
		new_points = pointPositions.collect { |xy|
			[xy[0].linlin(xmin,xmax,0,1),xy[1].linlin(ymin,ymax,0,1)];
		};
		fqs.postln;
		{ view.refresh }.defer;  // GUI updates must happen on AppClock
		fqs.scramble.do {
			|f,i|
			s.bind{
				Synth(\playSine,[
					\freq,f,
					\amp,f.explin(40,12000,-10,-30).dbamp / (len.sqrt),
					\atk, 0.25 * dur,
					\sus, 0.5 * (dur-(i*step)),
					\rel,0.25 * dur
				]);
			};
			(step).wait;
		};
		dur.wait;
		points = points ++ new_points;
	};
}).play(AppClock);

view.refresh;
)

