use strict;
use warnings;

use Test2::V0;

use OpenMP;
   
use Inline (
    C    => 'DATA',
    with => qw/OpenMP::Simple/,
);
   
my $omp = OpenMP->new;
   
for my $want_num_threads ( 1 .. 16 ) {
  note "$want_num_threads threads ...";

  $omp->env->omp_num_threads($want_num_threads);
  $omp->env->assert_omp_environment; # (optional) validates %ENV
  # call parallelized C function
  my $got_num_threads = _check_num_threads();
  is $got_num_threads, $want_num_threads, "OpenMP runtime detects and returns expected number of threads";

  # SvPV
  my $input = "Hello, OpenMP::Simple!";
  my $output = testSvPV($input);
  is $input, $output, "SvPV (string) value read by multiple threads is the same as the one set originally";

  # SvIV
  $output = testSvIV($want_num_threads);
  is $want_num_threads, $output, "SvIV (integer) value read by multiple threads is the same as the one set originally";

  # SvNV
  my $double = 42.42;
  $output = testSvNV($double);
  is $double, $output, "SvNV (float, double, or long double) value read by multiple threads is the same as the one set originally";

  # SvTRUE
  $output = testSvTRUE(undef);
  is 0, $output, "expected falsy";
  $output = testSvTRUE("");
  is 0, $output, "expected falsy";
  $output = testSvTRUE("0");
  is 0, $output, "expected falsy";
  $output = testSvTRUE("0E0");
  is 1, $output, "expected truthy";
  $output = testSvTRUE(0);
  is 0, $output, "expected falsy";
  $output = testSvTRUE(1);
  is 1, $output, "expected truthy";
  $output = testSvTRUE(-1);
  is 1, $output, "expected truthy";
  $output = testSvTRUE("Hello");
  is 1, $output, "expected truthy";
  $output = testSvTRUE(" ");
  is 1, $output, "expected truthy";
  $output = testSvTRUE([]);
  is 1, $output, "expected truthy";
  $output = testSvTRUE({});
  is 1, $output, "expected truthy";

  # SvTYPE
  # SvCUR
  # SvLEN
  # SvREFCOUNT
}

done_testing(); # Automatically determines the number of tests
 
__DATA__
__C__
 
/* C function parallelized with OpenMP */
int _check_num_threads() {
  int ret = 0;
    
  PerlOMP_GETENV_BASIC
   
  #pragma omp parallel
  {
    #pragma omp single
    ret = omp_get_num_threads();
  }
 
  return ret;
}

SV* testSvPV(SV* input) {
    PerlOMP_GETENV_BASIC
    // Ensure the input is a string or can be stringified
    STRLEN len;
    char *strIn;
    SV* output;

    #pragma omp parallel private(str)
    {
      strIn = SvPV(input, len); // Fetch the string value and its length
      #pragma omp single        // Create a new Perl scalar to return the value
      {
        output = newSVpv(strIn, len);
      }
    }

    return output;
}

SV* testSvIV(SV* input) {
    PerlOMP_GETENV_BASIC

    IV intIn;    // To hold the integer value of the input
    SV* output;  // To hold the output scalar

    #pragma omp parallel private(intIn)
    {
        intIn = SvIV(input); // Fetch the integer value from the input scalar
        #pragma omp single   // Ensure only one thread creates the output scalar
        {
            output = newSViv(intIn); // Create a new Perl scalar to hold the integer
        }
    }
    return output;
}

SV* testSvNV(SV* input) {
    PerlOMP_GETENV_BASIC

    NV numIn;    // To hold the numeric value of the input
    SV* output;  // To hold the output scalar

    #pragma omp parallel private(numIn)
    {
        numIn = SvNV(input); // Fetch the numeric value from the input scalar
        #pragma omp single   // Ensure only one thread creates the output scalar
        {
            output = newSVnv(numIn); // Create a new Perl scalar to hold the numeric value
        }
    }
    return output;
}

/*
#  +-----------------+--------------------+
#  | Perl Value      | Truthiness (SvTRUE)|
#  +-----------------+--------------------+
#  | undef           | 0 (False)          |
#  | "" (empty)      | 0 (False)          |
#  | "0"             | 0 (False)          |
#  | "0E0"           | 1 (True)           |
#  | 0               | 0 (False)          |
#  | 1               | 1 (True)           |
#  | -1              | 1 (True)           |
#  | "Hello"         | 1 (True)           |
#  | " " (space)     | 1 (True)           |
#  | [] (empty array)| 1 (True)           |
#  | {} (empty hash) | 1 (True)           |
#  +-----------------+--------------------+
*/

SV* testSvTRUE(SV* input) {
    PerlOMP_GETENV_BASIC

    bool isTrue;  // To hold the truthiness value
    SV* output;   // To hold the output scalar

    #pragma omp parallel private(isTrue)
    {
        isTrue = SvTRUE(input); // Check the truthiness of the input scalar
        #pragma omp single     // Ensure only one thread creates the output scalar
        {
            output = newSViv(isTrue); // Create a new Perl scalar with the truthiness as an integer (1 or 0)
        }
    }
    return output;
}


__END__

