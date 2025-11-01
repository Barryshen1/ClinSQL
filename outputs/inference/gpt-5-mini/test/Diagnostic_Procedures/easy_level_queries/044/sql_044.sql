WITH mcs_procs AS (
  -- identify procedure records whose description indicates mechanical circulatory support
  SELECT DISTINCT
    pi.subject_id,
    pi.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON pi.icd_code = dp.icd_code
   AND pi.icd_version = dp.icd_version
  WHERE dp.long_title IS NOT NULL
    AND REGEXP_CONTAINS(
      LOWER(dp.long_title),
      r'(ecmo|extracorporeal|balloon pump|intra[- ]aortic|ventricular assist|v[ -]?a[d]?|lvad|impella|tandemheart|pvad|percutaneous ventricular|cardiac assist|mechanical circulatory)'
    )
),
per_patient_counts AS (
  -- for the cohort (male, age 56-66), count distinct MCS procedure codes per patient (0 if none)
  SELECT
    p.subject_id,
    COALESCE(COUNT(m.icd_code), 0) AS distinct_mcs_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  LEFT JOIN mcs_procs AS m
    ON p.subject_id = m.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
  GROUP BY p.subject_id
)
-- compute the standard deviation (sample) of the per-patient distinct-procedure counts
SELECT
  STDDEV_SAMP(distinct_mcs_proc_count) AS sd_distinct_mcs_procs,
  COUNT(*) AS n_patients,
  AVG(distinct_mcs_proc_count) AS mean_distinct_mcs_procs
FROM per_patient_counts;