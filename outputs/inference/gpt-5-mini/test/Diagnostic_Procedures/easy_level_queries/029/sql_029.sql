WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),

pm_icd_codes AS (
  -- ICD procedure codes whose description suggests pacemaker/ICD procedures.
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%pacemaker%'
     OR LOWER(long_title) LIKE '%defibrillator%'
     OR LOWER(long_title) LIKE '%implantable cardioverter%'
     OR LOWER(long_title) LIKE '%aicd%'
     OR LOWER(long_title) LIKE '%cardioverter%'
     OR LOWER(long_title) LIKE '%generator%'
),

per_patient_counts AS (
  -- Count distinct pacemaker/ICD procedure codes per patient (include zeros)
  SELECT
    c.subject_id,
    COUNT(DISTINCT CASE
      WHEN k.icd_code IS NOT NULL THEN CONCAT(p.icd_version, '||', p.icd_code)
      ELSE NULL
    END) AS distinct_pm_icd_proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
  LEFT JOIN pm_icd_codes k
    ON p.icd_code = k.icd_code
   AND p.icd_version = k.icd_version
  GROUP BY c.subject_id
)

SELECT
  -- APPROX_QUANTILES(..., 4) returns an array with quartile cut points:
  -- OFFSET(0) = min, OFFSET(1) = 25th percentile, OFFSET(2) = median, OFFSET(3) = 75th, OFFSET(4) = max
  quantiles[OFFSET(1)] AS p25_approx,
  -- also return as integer (rounded) to reflect a count if desired
  CAST(ROUND(quantiles[OFFSET(1)]) AS INT64) AS p25_approx_rounded
FROM (
  SELECT APPROX_QUANTILES(distinct_pm_icd_proc_count, 4) AS quantiles
  FROM per_patient_counts
);