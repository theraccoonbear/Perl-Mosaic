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
use POSIX;

my $tile_set = 'misc';
my $cell_size = 20;
my $sample_size = 20;
my $output_size = 0;
my $src_file;

GetOptions(
	'tiles=s' => \$tile_set,
	'cell=i' => \$cell_size,
	'sample=i' => \$sample_size,
	'output=i' => \$output_size,
	'src=s' => \$src_file
);

$output_size = $output_size < 1 ? $sample_size : $output_size;

# Disable output buffering
select((select(STDOUT), $|=1)[0]);

my $mosaic_root = "$FindBin::Bin/mosaic/";
my $tile_path = $mosaic_root . 'tiles/' . $tile_set . '/';
my $src_path = $mosaic_root . 'source/';
my $gen_path = $mosaic_root . 'generated/';
my $dbg_path = $mosaic_root . 'debug/';

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
	
	my $cnt = 0;
	foreach my $x (($ox + 1)..($ox + 1 + $w)) {
		foreach my $y (($oy + 1)..($oy + 1 + $h))  {
			my $index = $im->getPixel($x-1,$y-1);
			my ($r,$g,$b) = $im->rgb($index);
		
			
			$r_avg += $r;
			$g_avg += $g;
			$b_avg += $b;
			$cnt++;
		}
	}
	
	my $r_avg_val = $r_avg / $cnt;
	my $g_avg_val = $g_avg / $cnt;
	my $b_avg_val = $b_avg / $cnt;
	my $average = {
		r => $r_avg_val,
		g => $g_avg_val,
		b => $b_avg_val
	};
	
	return $average;
	
} # avgImg()

sub saveJpg {
	my $img = shift @_;
	my $path = shift @_;
	my $qual = shift @_ || 80;
	
	my $jpg_data = $img->jpeg($qual);

	open(JPEGFH ,">$path") or die "Can't write $path: $!";
	binmode JPEGFH;
	print JPEGFH $jpg_data;
	close JPEGFH;
}

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
	my $cache_key = "TILE::${tile_set}::${f}";
	if (-f $image_path && $f =~ m/\.(jpe?g)$/gi) {
		my $tmp_img = GD::Image->newFromJpeg($image_path);
		my ($tw, $th) = $tmp_img->getBounds();
		$tiles->{$f} = GD::Image->new($output_size, $output_size); #$cell_size, $cell_size);
		#$image->copyResized($sourceImage,$dstX,$dstY,$srcX,$srcY,$destW,$destH,$srcW,$srcH)
		$tiles->{$f}->copyResized($tmp_img, 0, 0, 0, 0, $output_size, $output_size, $tw, $th); # $cell_size, $cell_size, $tw ,$th);
		saveJpg($tiles->{$f}, $dbg_path . $f);
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

my $image_path = $src_path . $src_file;

my $src = GD::Image->newFromJpeg($image_path);
my ($width, $height) = $src->getBounds();

my $horiz = ceil($width / $sample_size);
my $vert = ceil($height / $sample_size);

my $output_width = $horiz * $output_size;
my $output_height = $vert * $output_size;

my $gen_file = $gen_path . $tile_set . '-' . $src_file;
my $gen = GD::Image->new($output_width, $output_height);


print <<__JOB;
Source Image: $image_path
Source Dimensions: $width x $height
Sample Size: $sample_size
Grid Dimensions: $horiz x $vert
Output Size: $output_size
Generated Dimensions: $output_width x $output_height

__JOB


#for (my $y = 0; $y < $height; $y += $sample_size) { # $cell_size) {
#	for (my $x = 0; $x < $width; $x += $sample_size) { # $cell_size) {
for (my $y_idx = 0; $y_idx < $vert; $y_idx++) { # $cell_size) {
	for (my $x_idx = 0; $x_idx < $horiz; $x_idx++) { # $cell_size) {
		
		my $ix = $x_idx * $sample_size;
		my $iy = $y_idx * $sample_size;
		my $ox = $x_idx * $output_size;
		my $oy = $y_idx * $output_size;
		
		
		my $avg = avgImg($src, $ix, $iy, $sample_size, $sample_size); #$cell_size, $cell_size);
		my $closest = 'XXX';
		my $closest_dist = 100000000000;
		foreach my $clr (keys %$tile_avg_color) {
			my $dist = colorDist($tile_avg_color->{$clr}, $avg);
			if ($dist < $closest_dist) {
				$closest_dist = $dist;
				$closest = $clr;
			}
		}
		#$image->copyResized($sourceImage,$dstX,$dstY,$srcX,$srcY,$destW,$destH,$srcW,$srcH)
		#$gen->copyResized($tiles->{$closest}, $ox, $oy, $ix, $iy, $output_size, $output_size, $output_size, $output_size);
		$gen->copy($tiles->{$closest}, $ox, $oy, 0, 0, $output_size, $output_size);
	}
	my $percent = floor(($y_idx / $vert) * 1000) / 10;
	print "${percent}% complete.\n";
}

my $jpg_data = $gen->jpeg(80);

open(JPEGFH ,">$gen_file") or die "Can't write $gen_file: $!";
binmode JPEGFH;
print JPEGFH $jpg_data;
close JPEGFH;