#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use Data::Dumper;
use GD::Image;
use Cache::FileCache;
use Color::Similarity::HCL qw (rgb2hcl distance_hcl);

# Disable output buffering
select((select(STDOUT), $|=1)[0]);

my $mosaic_root = "$FindBin::Bin/mosaic/";
my $tile_path = $mosaic_root . 'tiles/';
my $src_path = $mosaic_root . 'source/';

my $cache = new Cache::FileCache({
	cache_root => $mosaic_root . 'tmp',
	namespace  => 'Mosaic'
});

my $cell_size = 20;


opendir DFH, $tile_path;
my @FILES = readdir DFH;
closedir DFH;

sub avgImg {
	my $im = shift @_;
	
	my ($width, $height) = $im->getBounds();
	
	my $ox = shift @_ || 0;
	my $oy = shift @_ || 0;
	my $w = shift @_ || $width;
	my $h = shift @_ || $height;
	
	my $r_avg = 0;
	my $g_avg = 0;
	my $b_avg = 0;
	my $min_r = 10000;
	my $min_g = 10000;
	my $min_b = 10000;
	my $max_r = 0;
	my $max_g = 0;
	my $max_b = 0;
	my $cnt = 0;
	foreach my $x (($ox + 1)..($ox + 1 + $w)) {
		foreach my $y (($oy + 1)..($oy + 1 + $h))  {
			my $index = $im->getPixel($x-1,$y-1);
			my ($r,$g,$b) = $im->rgb($index);
			
			#if ($r < $min_r) { $min_r = $r; }
			#if ($r > $max_r) { $max_r = $r; }
			#if ($g < $min_g) { $min_g = $g; }
			#if ($g > $max_g) { $max_g = $g; }
			#if ($b < $min_b) { $min_b = $b; }
			#if ($b > $max_b) { $max_b = $b; }
			
			$r_avg += $r;
			$g_avg += $g;
			$b_avg += $b;
			$cnt++;
			#if (!($cnt % 1000)) {
			#	print STDERR ".";
			#}
		}
	}
	
	my $r_avg_val = $r_avg / $cnt;
	my $g_avg_val = $g_avg / $cnt;
	my $b_avg_val = $b_avg / $cnt;
	my $average = {
		r => $r_avg_val,
		g => $g_avg_val,
		b => $b_avg_val,
		#min_r => $min_r,
		#min_g => $min_g,
		#min_b => $min_b,
		#max_r => $max_r,
		#max_g => $max_g,
		#max_b => $max_b,
	};
	
	return $average;
	
} # avgImg()

sub colorDist {
	my $c1 = shift @_;
	my $c2 = shift @_;
	
	my $color_1 = rgb2hcl($c1->{r}, $c1->{g}, $c1->{b});
	my $color_2 = rgb2hcl($c2->{r}, $c2->{g}, $c2->{b});
	
  my $d = distance_hcl($color_1, $color_2);
	return $d;
}

my $tile_avg_color = {};

foreach my $f (@FILES) {
	
	my $image_path  = $tile_path . $f;
	my $cache_key = "TILE:$f";
	if (-f $image_path && $f =~ m/\.(jpe?g)$/gi) {
		$tile_avg_color->{$f} = $cache->get($cache_key);
		if (!$tile_avg_color->{$f}) {
			my $im = GD::Image->newFromJpeg($image_path);
			my $average = avgImg($im);
			print "$f = ($average->{r}, $average->{g}, $average->{b})\n";
			$cache->set($cache_key, $average);
			$tile_avg_color->{$f} = $average;
		}
	}
}


my $src = GD::Image->newFromJpeg($src_path . 'madison-skyline-medium.jpg');
my ($width, $height) = $src->getBounds();

print <<__START;
<!DOCTYPE html>
<html>
	<head>
		<title>Mosaic</title>
		<style type="text/css">
			html, body {
				overflow-x: scroll;
			}
			
			div {
				margin: 0px;
				padding: 0px;
				cell-padding: 0px;
				border: 0px;
				float: left;
				display: inline-block;
				width: ${cell_size}px;
				height: ${cell_size}px;
			}
			
			img {
				width: ${cell_size}px;
				height: ${cell_size}px;
			}
		</style>
	</head>
	<body>
__START

#print "<table>\n";

for (my $y = 0; $y < $height; $y += $cell_size) {
	#print "  <tr>\n";
	for (my $x = 0; $x < $width; $x += $cell_size) {
		my $avg =  avgImg($src, $x, $y, $cell_size, $cell_size);
		my $closest = 'XXX';
		my $closest_dist = 100000000000;
		foreach my $clr (keys %$tile_avg_color) {
			my $dist = colorDist($tile_avg_color->{$clr}, $avg);
			if ($dist < $closest_dist) {
				$closest_dist = $dist;
				$closest = $clr;
			}
		}
		print "<div>";
		print "<img src=\"../tiles/$closest\">";
		print "</div>";
	}
	print "<br>";
	#print "  </tr>\n";
}
print <<__END;
</table>
</body>
</html>
__END


