WITH heart_failure_admissions AS (
  SELECT DISTINCT ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = CAST(49 AS INT64)
    AND diag.seq_num = 1
    AND diag.icd_version = 'ICD-10-CM'
    AND diag.icd_code LIKE 'I50%'
)
SELECT
  PERCENTILE_CONT(0.75) OVER() AS p75_nadir_hemoglobin_g_per_dL
FROM (
  SELECT MIN(le.valuenum) AS nadir_hgb
  FROM heart_failure_admissions hfa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hfa.hadm_id = le.hadm_id
  WHERE le.itemid = CAST(51222 AS STRING)  -- Hemoglobin
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY hfa.hadm_id
);