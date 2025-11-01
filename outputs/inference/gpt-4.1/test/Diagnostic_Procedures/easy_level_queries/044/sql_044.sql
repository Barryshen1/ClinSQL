WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 56 AND 66
),
mcs_procedures AS (
  SELECT
    p.subject_id,
    pr.icd_code,
    pr.icd_version
  FROM cohort p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  WHERE pr.icd_code IN (
    '37.61', -- IABP
    '37.66', '37.62', '37.65', '37.68', -- VAD
    '39.65'  -- ECMO
  )
),
distinct_mcs_count AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT m.icd_code) AS num_mcs_types
  FROM cohort c
  LEFT JOIN mcs_procedures m
    ON c.subject_id = m.subject_id
  GROUP BY c.subject_id
)
SELECT
  STDDEV_SAMP(num_mcs_types) AS sd_distinct_mcs_per_patient
FROM distinct_mcs_count;