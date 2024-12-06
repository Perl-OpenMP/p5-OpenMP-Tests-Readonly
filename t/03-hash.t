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

  my $hash = {
    key1 => 42,
    key2 => 84,
    key3 => 168,
    key4 => 2*168,
  };

  my $iterations = 1000000;

  # Call the C function that fetches values in parallel
  my $output = test_hv_fetch($hash, [keys %$hash],  $iterations);
  is $output, 4, "testing hv_fetch for expected count";

  $output = test_hv_exists($hash, [keys %$hash],  $iterations);
  is $output, 4, "testing hv_exists for expected count";

  # don't think hv_iterinit and hv_iternext are thread safe
  #$output = test_hv_iternext($hash, [keys %$hash],  $iterations);
  #is $output, 4, "testing hv_iterinit and hv_iternext for expected count";

  $output = test_hv_iterval($hash, $iterations);
  is $output, 4, "testing hv_iterval for expected count";

  $output = test_hv_keys($hash, $iterations);
  is $output, 4, "testing HvKEYS for expected count";

  $output = test_hv_usedkeys($hash, $iterations);
  is $output, 4, "testing HvUSEDKEYS for expected count";

  $output = test_hv_totalkeys($hash, $iterations);
  is $output, 4, "testing HvTOTALKEYS for expected count";

  $output = test_hv_array($hash, $iterations);
  is $output, 4, "testing HvARRAY for expected count";
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

// Function to start parallel fetch using OpenMP in an attempt
// to induce some sort of memory allocation issues
SV* test_hv_fetch(HV *hash, AV *keys, int iterations) {
    // Get the number of keys in the provided AV* (key array)
    int key_count = av_len(keys) + 1;  // av_len is 0-based, so we add 1 to get the total count

    PerlOMP_GETENV_BASIC

    // Convert the result (int found_count) to an SV (Scalar Value)
    SV *result;
        
    // Parallelize the loop using OpenMP
    #pragma omp parallel
    {
      int found_count;
      #pragma omp for
      for (int i = 0; i < iterations; i++) {
        found_count = 0;
        for (int j = 0; j < key_count; j++) {
            SV *key_sv = *av_fetch(keys, j, 0);  // Fetch the key from the Perl array
            if (key_sv) {
                STRLEN len;
                char *key = SvPV(key_sv, len);  // Get the key as a C string
                SV **value = hv_fetch(hash, key, len, 0); // Perform hv_fetch
                if (value != NULL) {
                    found_count++;
                }
            }
        }
      }

      #pragma omp single
      result = newSViv(found_count);  // Create a new SV from the found count (int)
    }

    return result;
}

// Function to start parallel checks using hv_exists in an attempt
// to induce memory allocation issues or segmentation faults
SV* test_hv_exists(HV *hash, AV *keys, int iterations) {
    // Get the number of keys in the provided AV* (key array)
    int key_count = av_len(keys) + 1;  // av_len is 0-based, so we add 1 to get the total count

    PerlOMP_GETENV_BASIC

    // Convert the result (int found_count) to an SV (Scalar Value)
    SV *result;
        
    // Parallelize the loop using OpenMP
    #pragma omp parallel
    {
      int found_count;
      #pragma omp for
      for (int i = 0; i < iterations; i++) {
        found_count = 0;
        for (int j = 0; j < key_count; j++) {
            SV *key_sv = *av_fetch(keys, j, 0);  // Fetch the key from the Perl array
            if (key_sv) {
                STRLEN len;
                char *key = SvPV(key_sv, len);  // Get the key as a C string
                // Check if the key exists in the hash
                if (hv_exists(hash, key, len)) {
                    found_count++;  // Increment count if key exists
                }
            }
        }
      }

      #pragma omp single
      result = newSViv(found_count);  // Create a new SV from the found count (int)
    }

    return result;
}

// Function to simulate parallel access to the same hash entry using hv_iterval
SV* test_hv_iterval(HV *hash, int iterations) {
    // Result to store the count of accesses
    int found_count = 0;

    PerlOMP_GETENV_BASIC
    
    // Initialize the result variable (this is just an example, the logic can be adjusted based on your needs)
    SV *result = NULL;

    // Iterate over the hash keys
    hv_iterinit(hash);

    for (int i = 0; i < iterations; i++) {
      HE *he;
      found_count = 0;
      while ((he = hv_iternext(hash)) != NULL) {
        #pragma omp parallel
        {
          // Access the value associated with this hash entry using hv_iterval
          SV *entry_value = hv_iterval(hash, he);  // This gets the value corresponding to this key
          // We simulate some processing (could be a dummy check or access to the value)
          if (entry_value) {
            // Parallelize the loop where threads are accessing the same hash entry
            // Access the value at the same hash entry
            SV *value = hv_iterval(hash, he);  // All threads access the same entry
            #pragma omp single
            if (value != NULL) {
                found_count++;  // Count successful accesses
            }
          }
        }
      }
    }

    // Convert the result to an SV (Scalar Value) and return
    result = newSViv(found_count);
    return result;
}

// Function to test HvKEYS in a parallel context
//  Note: attempt to break up "omp parallel" and "omp for" or
//  to use an "omp single" to get the count results in a compiler
//  error regarding the expansion of HeKEY ...
SV* test_hv_keys(HV *hash, int iterations) {
    int total_keys = 0;

    PerlOMP_GETENV_BASIC

    // Parallelize the loop using OpenMP
    int my_num_keys = 0;
    #pragma omp parallel for
    for (int i = 0; i < iterations; i++) {
      // HvKEYS provides the number of keys in the hash
      my_num_keys = HvKEYS(hash);
      int tid = omp_get_thread_num();
      if (tid == 0) {
        total_keys = my_num_keys;
      }
    }

    // Return the result as a Perl scalar value (SV)
    return newSViv(total_keys);
}

SV* test_hv_usedkeys(HV *hash, int iterations) {
    int total_keys = 0;

    PerlOMP_GETENV_BASIC

    // Parallelize the loop using OpenMP
    int my_num_keys = 0;
    #pragma omp parallel for
    for (int i = 0; i < iterations; i++) {
      // HvKEYS provides the number of keys in the hash
      my_num_keys = HvUSEDKEYS(hash);
      int tid = omp_get_thread_num();
      if (tid == 0) {
        total_keys = my_num_keys;
      }
    }

    // Return the result as a Perl scalar value (SV)
    return newSViv(total_keys);
}

SV* test_hv_totalkeys(HV *hash, int iterations) {
    int total_keys = 0;

    PerlOMP_GETENV_BASIC

    // Parallelize the loop using OpenMP
    int my_num_keys = 0;
    #pragma omp parallel for
    for (int i = 0; i < iterations; i++) {
      // HvKEYS provides the number of keys in the hash
      my_num_keys = HvUSEDKEYS(hash);
      int tid = omp_get_thread_num();
      if (tid == 0) {
        total_keys = my_num_keys;
      }
    }

    // Return the result as a Perl scalar value (SV)
    return newSViv(total_keys);
}

// Function to test HvARRAY() in parallel with each thread calling it
//  Note: attempt to break up "omp parallel" and "omp for" or
//  to use an "omp single" to get the count results in a compiler
//  error regarding the expansion of HeKEY ...
SV* test_hv_array(HV *hash, int iterations) {
    int total_keys = 0;

    PerlOMP_GETENV_BASIC

    // Parallelize using OpenMP, each thread calls HvARRAY and iterates independently
    #pragma omp parallel for
    for (int i = 0; i < iterations; i++) {
      HE **entries = HvARRAY(hash); // Each thread gets its own array of hash entries
      int my_num_keys = HvKEYS(hash);  // Get the number of keys in the hash
      int my_key_count = 0;
      for (int j = 0; j < my_num_keys; j++) {
        HE *entry = entries[j]; // Get the hash entry
// NOTE: this section is really sensitive to a rehash (?) - how can this be prevented? 
/*
        if (entry) {
          SV *key_sv = HeKEY(entry); // Get the key
          if (key_sv) {
            STRLEN len;
            char *key = SvPV(key_sv, len); // Convert to C string
            SV **value = hv_fetch(hash, key, len, 0); // Fetch value
            if (value) {
              my_key_count++;
            }
          }
        }
*/
      }
      int tid = omp_get_thread_num();
      if (tid == 0) {
        total_keys = my_num_keys;
      }
    }

    // Return the total found count as an SV
    return newSViv(total_keys);
}

//// exposes hv_iternext/iterinit as not thread safe
//SV* test_hv_iternext(HV *hash, AV *keys, int iterations) {
//    // Get the number of keys in the provided AV* (key array)
//    int key_count = av_len(keys) + 1;  // av_len is 0-based, so we add 1 to get the total count
//
//    // Set OpenMP environment for parallel execution
//    PerlOMP_GETENV_BASIC
//
//    // Convert the result (int found_count) to an SV (Scalar Value)
//    SV *result;
//        
//    // Parallelize the loop using OpenMP
//    #pragma omp parallel
//    {
//      // Initialize found_count inside the parallel block
//      int found_count = 0; 
//
//      #pragma omp for
//      for (int i = 0; i < iterations; i++) {
//        // Initialize hash iteration using hv_iterinit
//        HE *he;
//        hv_iterinit(hash);  // Initialize iteration over the hash
//        
//        // Iterate over the hash entries
//        while ((he = hv_iternext(hash)) != NULL) {  // Iterate over the hash entries
//            SV *key_sv = HeKEY(he);  // Fetch the key from the hash entry
//            if (key_sv) {
//                STRLEN len;
//                char *key = SvPV(key_sv, len);  // Get the key as a C string
//
//                // Perform hv_fetch for the current key
//                SV **value = hv_fetch(hash, key, len, 0);
//                if (value != NULL) {
//                    found_count++;  // Increment if key found
//                }
//            }
//        }
//      }
//
//      #pragma omp single
//      result = newSViv(found_count);  // Create a new SV from the found count (int)
//    }
//
//    return result;
//}

__END__

