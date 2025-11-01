WITH cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 63 AND 73
),
admission_procedures AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON c.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE d.long_title IS NULL 
     OR LOWER(d.long_title) LIKE '%cardiac%'
  GROUP BY c.hadm_id
)
SELECT 
  APPROX_QUANTILES(COALESCE(proc_count, 0), 1000)[OFFSET(750)] AS percentile_75
FROM admission_procedures;