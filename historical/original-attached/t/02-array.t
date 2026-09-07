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

  my $array_ref = [1 .. 1000 ];
  my $output = test_av_len($array_ref);

  is $output, scalar @$array_ref - 1, "Length of array is, as expected";

  $output = test_av_fetch($array_ref, 999, 0);
  is $output, $array_ref->[999], "av_fetch has behaved as expected";

  # NOTE: av_fetch breaks immediately in the case of a race condition (with 2 threads)
  # that are using it in a way causes the array to grow, even by a single element
  # $output = test_av_fetch($array_ref, 1000, 1);
  #is $output, undef, "av_fetch has behaved as expected";

  $output = test_av_exists($array_ref, 999);
  is $output, 1, "av_exists has behaved as expected with an index that does exist";
  $output = test_av_exists($array_ref, 1000);
  is $output, undef, "av_exists has behaved as expected with an index that doesn't exist";

  $output = test_av_fill_index($array_ref);
  is $output, scalar @$array_ref - 1, "AvFILL returns highest 'fill' index, as expected";

  $array_ref->[1010] = 1000;
  $output = test_av_fill_index($array_ref);
  is $output, 1010, "AvFILL returns highest 'fill' index after forcing array to grow, as expected";

#...some meat and potatoes here! WIP!
  #$array_ref = [1 .. 1000 ];
  #$output = test_av_double_elements($array_ref);
  #note $output;

  #$output = test_av_transform_parallel($array_ref);
  #is($output, $array_ref);
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

SV* test_av_len(SV* input) {
    PerlOMP_GETENV_BASIC // Ensures OpenMP environment variables are handled

    AV* array;
    int length = -1; // Default length if input is not an array
    SV* output;

    // Ensure the input is an array reference
    if (SvROK(input) && SvTYPE(SvRV(input)) == SVt_PVAV) {
        array = (AV*)SvRV(input);

        #pragma omp parallel
        {
            int local_len = av_len(array); // Get the highest index in the array
            #pragma omp critical
            {
                // OpenMP ensures safe access to shared resources
                length = local_len; 
            }
        }
    }

    // Create a new scalar to return the length
    output = newSViv(length);
    return output;
}

SV* test_av_fetch(SV* array_ref, int index, int autoextend) {
    PerlOMP_GETENV_BASIC // Ensures OpenMP environment variables are handled

    AV* array;
    SV** fetched_sv;
    SV* result;

    // Check if the input is an array reference
    if (SvROK(array_ref) && SvTYPE(SvRV(array_ref)) == SVt_PVAV) {
      array = (AV*)SvRV(array_ref);

      #pragma omp parallel private(fetched_sv)
      {
        fetched_sv = av_fetch(array, index, autoextend); // 0 = Do not auto-extend the array

        #pragma omp single
        {
          if (fetched_sv && *fetched_sv) {
            // Copy the fetched scalar for return
            result = newSVsv(*fetched_sv);
          } else {
            // Return undef if the index is out of bounds
            result = &PL_sv_undef;
          }
        }
      }
    } else {
        // Return undef if the input is not a valid array reference
        result = &PL_sv_undef;
    }

    return result;
}

SV* test_av_exists(SV* array_ref, int index) {
    PerlOMP_GETENV_BASIC // Ensures OpenMP environment variables are handled

    AV* array;
    SV* result;

    // Check if the input is an array reference
    if (SvROK(array_ref) && SvTYPE(SvRV(array_ref)) == SVt_PVAV) {
        array = (AV*)SvRV(array_ref);

        #pragma omp parallel
        {
            // Use av_exists to check if the index exists in the array
            int exists = av_exists(array, index); // Check if the element exists at 'index'

            #pragma omp single
            {
                if (exists) {
                    // Return a truthy value (e.g., 1) if the element exists at the index
                    result = newSViv(1);  // Truthy value
                } else {
                    // Return undef if the element does not exist
                    result = &PL_sv_undef;
                }
            }
        }
    } else {
        // Return undef if the input is not a valid array reference
        result = &PL_sv_undef;
    }

    return result;
}

SV* test_av_fill_index(SV* array_ref) {
    PerlOMP_GETENV_BASIC // Ensures OpenMP environment variables are handled

    AV* array;
    SV* result;
    I32 fill_index;

    // Check if the input is an array reference
    if (SvROK(array_ref) && SvTYPE(SvRV(array_ref)) == SVt_PVAV) {
        array = (AV*)SvRV(array_ref);

        #pragma omp parallel
        {
            // Use AvFILLp to get the current fill index of the array
            fill_index = AvFILLp(array);  // Get the fill index

            #pragma omp single
            {
                // Return the fill index as a scalar value
                result = newSViv(fill_index);
            }
        }
    } else {
        // Return undef if the input is not a valid array reference
        result = &PL_sv_undef;
    }

    return result;
}

// Function where each thread calls AvARRAY to get its own pointer to the underlying array
SV* test_av_double_elements(AV *av) {
    SV **array_data;
    I32 len, i;
    int my_num_elements;
    SV* num_elements;

    // Get the fill index (the highest valid index in the array)
    len = AvFILLp(av);  // get Fill index (last valid index)
    
    // Parallel region
    #pragma omp parallel private(array_data, i, my_num_elements)
    {
        // Each thread calls AvARRAY independently to get its own pointer to the array
        array_data = AvARRAY(av);  // Each thread gets its own pointer to the underlying array
        
        // Each thread accesses its own part of the array
        for (i = 0; i <= len; i++) {
            if (array_data[i]) {
                // Dereference the SV pointer to get the value of the element
                //if (SvNOK(array_data[i])) {  // Check if it is a numeric value
                //    double value = SvNV(array_data[i]);  // Get the numeric value
                    // Double the value - just do do some work ..
                    ++my_num_elements; 
                //}
            }
        }
        #pragma omp single
        {
          num_elements = newSViv(my_num_elements);
        }
    }
    return num_elements;
}

// generates a brand new AV for each thread that is a copy of the original,
// returns it as a reference - only one of the arrays created gets returned
SV* test_av_transform_parallel(SV* array_ref) {
    PerlOMP_GETENV_BASIC  // Ensure OpenMP environment variables are handled

    AV *original_array;
    SV **array_data;
    I32 len, i;
    SV *new_sv;
    AV *new_array = NULL;  // Final new array, initially NULL

    // Check if the input is an array reference
    if (SvROK(array_ref) && SvTYPE(SvRV(array_ref)) == SVt_PVAV) {
        original_array = (AV*)SvRV(array_ref);  // Get the original array (AV)
        len = AvFILLp(original_array) + 1;  // Get the length of the array (fill index + 1)
        array_data = AvARRAY(original_array);  // Access the underlying array (SV* array)

        // Parallel section: Each thread processes the array
        #pragma omp parallel private(i, new_array, new_sv)
        {
            // Each thread gets its own pointer to the entire array data
            SV **local_array_data = (SV **)malloc(len * sizeof(SV*));  // Allocate memory for local copy of array
            for (i = 0; i < len; i++) {
                local_array_data[i] = array_data[i];  // Copy the pointer from original array
            }

            // Process the array (e.g., double the values)
            #pragma omp for
            for (i = 0; i < len; i++) {
                if (local_array_data[i]) {
                    if (SvNOK(local_array_data[i])) {  // Check if the element is numeric
                        double value = SvNV(local_array_data[i]);  // Get the numeric value
                        value *= 2;  // Transform the value (double it)

                        // Create a new SV to hold the transformed value
                        new_sv = newSVnv(value);

                        // Replace the original element with the transformed value
                        local_array_data[i] = new_sv;  // Overwrite with the new SV
                    }
                }
            }

            // Only the first thread will take the transformed array and assign it to `new_array`
            #pragma omp single
            {
                if (new_array == NULL) {
                    new_array = newAV();  // Create a new array to hold the final results
                    // Copy the transformed data back into the new array
                    for (i = 0; i < len; i++) {
                        av_push(new_array, local_array_data[i]);  // Push each transformed element into the new array
                    }
                }
            }

            // Free the local array data allocated by each thread
            free(local_array_data);
        }

        // Return a reference to the new array (created by the first thread)
        return newRV_noinc((SV*)new_array);
    } else {
        // Return undef if the input is not a valid array reference
        return &PL_sv_undef;
    }
}
__END__

