WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'coronary artery bypass|coronary bypass|cabg')
),
cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 45 AND 55
),
patient_cabg_counts AS (
  SELECT 
    c.subject_id,
    COUNT(p.icd_code) AS cabg_count  -- Counts CABG procedures (0 if none)
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
  LEFT JOIN cabg_codes cc 
    ON p.icd_code = cc.icd_code AND p.icd_version = cc.icd_version
  GROUP BY c.subject_id
)
SELECT 
  APPROX_QUANTILES(cabg_count, 100)[OFFSET(25)] AS percentile_25
FROM patient_cabg_counts;