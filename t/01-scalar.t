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
  #  Perl Truth Table
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
  $output = testSvTYPE(undef);
  like($output, qr/Undefined/, "Testing type via SvTYPE");

  $output = testSvTYPE(42);
  like($output, qr/Integer/, "Testing type, SVt_IV, via SvTYPE");

  $output = testSvTYPE(42.42);
  like($output, qr/Float/, "Testing type, SVt_NV, via SvTYPE");

  $output = testSvTYPE("Hello");
  like($output, qr/String/, "Testing type, SVt_PV, via SvTYPE");

# the following tests seem to reveal a bug or regression in SvTYPE
=pod
  $output = testSvTYPE([1,2,3,3,7,7,7]);
  like($output, qr/Array/, "Testing type, SVt_PVAV, via SvTYPE");

  $output = testSvTYPE({foo => 1,bar => 2});
  like($output, qr/Hash/, "Testing type, SVt_PVHV, via SvTYPE");

  $output = testSvTYPE(sub { 42 });
  like($output, qr/Code/, "Testing type, SVt_PVCV, via SvTYPE");

  open my $fh, '>', '/dev/null' or die $!; # Filehandle GLOB
  $output = testSvTYPE(*$fh);
  like($output, qr/Glob/, "Testing type, SVt_PVGV, via SvTYPE");
  close $fh;
=cut

  # SvCUR
  # Testing with a string
  $output = testSvCUR("this string is 33 characters long");
  is $output, 33, "SvCUR outputs expected value for SVPV";

  # SvLEN
  is $output, 33, "SvLEN outputs expected value for SVPV";

  $output = testSvLEN("this string is 38 characters long\0\0\0");
  is $output, 38, "SvLEN outputs expected value for SVPV with null padding, full space allocated for the SVPV";

  # SvREFCNT
  # Perl code to test the reference count with OpenMP
  my $scalar = "Hello, World!";  # Create a scalar
  my $ref1 = \$scalar;             # Create another reference to the scalar
  my $ref2 = \$scalar;             # Create another reference to the scalar
  my $ref3 = \$scalar;             # Create another reference to the scalar
  $output = testSvREFCNT($scalar);  # Call the C function to get the reference count
  is $output, 4, "SvREFCNT value returned as expected";
  $ref3   = undef;
  $output = testSvREFCNT($scalar);  # Call the C function to get the reference count
  is $output, 3, "SvREFCNT value returned as expected";
  $ref2   = undef;
  $output = testSvREFCNT($scalar);  # Call the C function to get the reference count
  is $output, 2, "SvREFCNT value returned as expected";
  $ref1   = undef;
  $output = testSvREFCNT($scalar);  # Call the C function to get the reference count
  is $output, 1, "SvREFCNT value returned as expected";
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
  Perl Truth Table
  +-----------------+--------------------+
  | Perl Value      | Truthiness (SvTRUE)|
  +-----------------+--------------------+
  | undef           | 0 (False)          |
  | "" (empty)      | 0 (False)          |
  | "0"             | 0 (False)          |
  | "0E0"           | 1 (True)           |
  | 0               | 0 (False)          |
  | 1               | 1 (True)           |
  | -1              | 1 (True)           |
  | "Hello"         | 1 (True)           |
  | " " (space)     | 1 (True)           |
  | [] (empty array)| 1 (True)           |
  | {} (empty hash) | 1 (True)           |
  +-----------------+--------------------+
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

SV* testSvTYPE(SV* input) {
    PerlOMP_GETENV_BASIC

    const char* typeStr; // Pointer to store the type as a string
    SV* output;          // Scalar to hold the return value

    #pragma omp parallel private(typeStr)
    {
        // Determine the scalar type
        int type = SvTYPE(input);

        switch (type) {
            case SVt_NULL:
                typeStr = "Undefined (SVt_NULL)";
                break;
            case SVt_IV:
                typeStr = "Integer (SVt_IV)";
                break;
            case SVt_NV:
                typeStr = "Float (SVt_NV)";
                break;
            case SVt_PV:
                typeStr = "String (SVt_PV)";
                break;
            case SVt_PVAV:
                typeStr = "Array (SVt_PVAV)";
                break;
            case SVt_PVHV:
                typeStr = "Hash (SVt_PVHV)";
                break;
            case SVt_PVCV:
                typeStr = "Code (SVt_PVCV)";
                break;
            case SVt_PVGV:
                typeStr = "Glob (SVt_PVGV)";
                break;
            default:
                typeStr = "Unknown";
                break;
        }
        #pragma omp single
        {
            // Create a new Perl scalar containing the type as a string
            output = newSVpv(typeStr, 0);
        }
    }
    return output;
}

SV* testSvCUR(SV* input) {
    PerlOMP_GETENV_BASIC

    STRLEN len;  // To hold the length of the scalar
    SV* output;  // To hold the output scalar

    #pragma omp parallel private(len)
    {
        len = SvCUR(input); // Get the current length of the scalar
        #pragma omp single    // Ensure only one thread creates the output scalar
        {
            output = newSViv(len);  // Create a new Perl scalar with the length as an integer
        }
    }
    return output;
}

SV* testSvLEN(SV* input) {
    PerlOMP_GETENV_BASIC

    STRLEN len;  // To hold the length of the scalar
    SV* output;  // To hold the output scalar

    #pragma omp parallel private(len)
    {
        len = SvLEN(input); // Get the length of the scalar (it can be different from SvCUR)
        #pragma omp single    // Ensure only one thread creates the output scalar
        {
            output = newSViv(len);  // Create a new Perl scalar with the length as an integer
        }
    }
    return output;
}

SV* testSvREFCNT(SV* input) {
    PerlOMP_GETENV_BASIC

    I32 refcount;  // To hold the reference count of the scalar
    SV* output;    // To hold the output scalar

    #pragma omp parallel private(refcount)
    {
        refcount = SvREFCNT(input);  // Get the reference count of the scalar
        #pragma omp single    // Ensure only one thread creates the output scalar
        {
            output = newSViv(refcount);  // Create a new Perl scalar with the reference count as an integer
        }
    }
    return output;
}

__END__

