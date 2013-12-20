#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use Data::Dumper;
use GD::Image;
use Cache::FileCache;
use Color::Similarity::HCL qw (rgb2hcl distance_hcl);
use Getopt::Long;
use Carp;

my $tile_set = 'misc';
my $cell_size = 20;
my $src_file;

GetOptions(
	'tiles=s' => \$tile_set,
	'cell=i' => \$cell_size,
	'src=s' => \$src_file
);


# Disable output buffering
select((select(STDOUT), $|=1)[0]);

my $mosaic_root = "$FindBin::Bin/mosaic/";
my $tile_path = $mosaic_root . 'tiles/' . $tile_set . '/';
my $src_path = $mosaic_root . 'source/';
my $gen_path = $mosaic_root . 'generated/';

my $cache = new Cache::FileCache({
	cache_root => $mosaic_root . 'tmp',
	namespace  => 'Mosaic'
});


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
my $tiles = {};

foreach my $f (@FILES) {
	
	my $image_path  = $tile_path . $f;
	my $cache_key = "TILE:$f";
	if (-f $image_path && $f =~ m/\.(jpe?g)$/gi) {
		my $tmp_img = GD::Image->newFromJpeg($image_path);
		print Dumper($tmp_img);
		my ($tw, $th) = $tmp_img->getBounds();
		$tiles->{$f} = GD::Image->new($cell_size, $cell_size);
		
		$tiles->{$f}->copyResized($tmp_img, 0, 0, 0, 0, $cell_size, $cell_size, $tw ,$th);
		#$image->copyResized($sourceImage,$dstX,$dstY, $srcX,$srcY,$destW,$destH,$srcW,$srcH)
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

my $src = GD::Image->newFromJpeg($src_path . $src_file);
my ($width, $height) = $src->getBounds();


my $gen_file = $gen_path . $src_file;
my $gen = GD::Image->new($width, $height);


#print <<__START;
#<!DOCTYPE html>
#<html>
#	<head>
#		<title>Mosaic</title>
#		<style type="text/css">
#			html, body {
#				overflow-x: scroll;
#			}
#			
#			div {
#				margin: 0px;
#				padding: 0px;
#				cell-padding: 0px;
#				border: 0px;
#				float: left;
#				display: inline-block;
#				width: ${cell_size}px;
#				height: ${cell_size}px;
#			}
#			
#			img {
#				width: ${cell_size}px;
#				height: ${cell_size}px;
#			}
#		</style>
#	</head>
#	<body>
#__START

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
		
		$gen->copy($tiles->{$closest}, $x, $y, 0, 0, $cell_size, $cell_size);
		#print "<div>";
		#print "<img src=\"../tiles/$closest\">";
		#print "</div>";
	}
	#print "<br>";
	#print "  </tr>\n";
}

my $jpg_data = $gen->jpeg(80);
#open (DISPLAY,"| display -") || die;
open(JPEGFH ,">$gen_file") or die "Can't write $gen_file: $!";
binmode JPEGFH;
print JPEGFH $jpg_data;
close JPEGFH;

#print <<__END;
#</table>
#</body>
#</html>
#__END


