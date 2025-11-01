WITH upper_gi_bleed_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    LOWER(long_title) LIKE '%upper gastrointestinal hemorrhage%'
    OR LOWER(long_title) LIKE '%hematemesis%'
    OR LOWER(long_title) LIKE '%melena%'
    OR LOWER(long_title) LIKE '%varices with bleeding%'
    OR LOWER(long_title) LIKE '%ulcer with hemorrhage%'
),
primary_upper_gi_bleed_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN upper_gi_bleed_codes codes
    ON diag.icd_code = codes.icd_code AND diag.icd_version = codes.icd_version
  WHERE
    diag.seq_num = 1 -- primary diagnosis
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
admission_los AS (
  SELECT
    TIMESTAMP_DIFF(dischtime, admittime, SECOND)/86400.0 AS los_days
  FROM primary_upper_gi_bleed_admissions
  WHERE TIMESTAMP_DIFF(dischtime, admittime, SECOND) > 0
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS los_25th_percentile_days
FROM admission_los;