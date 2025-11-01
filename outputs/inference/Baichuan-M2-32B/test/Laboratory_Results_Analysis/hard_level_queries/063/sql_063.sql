WITH pe_icd AS (
     -- ICD codes for PE
   ),
   cohort AS (
     -- female patients aged 53-63 with PE
   ),
   abnormal_labs AS (
     -- abnormal lab events for the cohort in first 72 hours
   ),
   instability_scores AS (
     -- compute instability score per admission
   ),
   percentiles AS (
     -- compute 75th percentile
   ),
   high_score_group AS (
     -- admissions with score >= 75th percentile
   ),
   high_score_stats AS (
     -- compute mortality, mean_los, and abnormal lab rate for high-score group
   ),
   control_group AS (
     -- compute abnormal lab rate for all inpatients in first 72 hours
   )
   SELECT ...;