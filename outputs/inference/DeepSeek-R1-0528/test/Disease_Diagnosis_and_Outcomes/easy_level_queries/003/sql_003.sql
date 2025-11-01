WITH cohort AS (
  SELECT
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
      ON pat.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON adm.hadm_id = diag.hadm_id 
      AND adm.subject_id = diag.subject_id
  WHERE
    pat.gender = 'F'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes (410-414)
      (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^(410|411|412|413|414)'))
      OR
      -- ICD-10 codes (I20-I25)
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^(I20|I21|I22|I23|I24|I25)'))
    )
    -- Age 40-50 at admission (approximated using anchor_year)
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 40 AND 50
)
SELECT
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(25)] AS los_25th_percentile
FROM cohort;