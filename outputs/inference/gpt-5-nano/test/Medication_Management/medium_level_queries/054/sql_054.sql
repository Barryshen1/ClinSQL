WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 56 AND 66
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di2
        ON di.icd_code = di2.icd_code AND di.icd_version = di2.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND REGEXP_CONTAINS(LOWER(di2.long_title), r'(?i)diabetes')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di2
        ON di.icd_code = di2.icd_code AND di.icd_version = di2.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND REGEXP_CONTAINS(LOWER(di2.long_title), r'(?i)heart failure|congestive heart failure')
    )
)

SELECT
  COUNT(*) AS total_cohort,
  SUM(CASE WHEN first48_used = 1 THEN 1 ELSE 0 END) AS n_first48,
  SUM(CASE WHEN final24_used = 1 THEN 1 ELSE 0 END) AS n_final24,
  SAFE_DIVIDE(SUM(CASE WHEN first48_used = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS pct_first48,
  SAFE_DIVIDE(SUM(CASE WHEN final24_used = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS pct_final24,
  (SAFE_DIVIDE(SUM(CASE WHEN final24_used = 1 THEN 1 ELSE 0 END), COUNT(*)) 
     - SAFE_DIVIDE(SUM(CASE WHEN first48_used = 1 THEN 1 ELSE 0 END), COUNT(*))
  ) * 100 AS net_change_pp
FROM (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    -- Flags indicating exposure in each window
    (CASE WHEN EXISTS (
       SELECT 1
       FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
       WHERE pr.subject_id = e.subject_id
         AND pr.hadm_id = e.hadm_id
         AND REGEXP_CONTAINS(LOWER(pr.drug), r'(?i)(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide)')
         AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR)
     ) THEN 1 ELSE 0 END) AS first48_used,
    (CASE WHEN EXISTS (
       SELECT 1
       FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
       WHERE pr.subject_id = e.subject_id
         AND pr.hadm_id = e.hadm_id
         AND REGEXP_CONTAINS(LOWER(pr.drug), r'(?i)(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide)')
         AND pr.stoptime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR)
         AND pr.starttime <= e.dischtime
     ) THEN 1 ELSE 0 END) AS final24_used
  FROM eligible_admissions e
) t;