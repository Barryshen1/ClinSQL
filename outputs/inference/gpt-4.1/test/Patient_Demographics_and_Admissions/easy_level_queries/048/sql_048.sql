WITH heart_failure_codes AS (
  -- ICD-10: I50.x, ICD-9: 428.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
hf_first_admissions AS (
  -- Get first admission for each eligible patient, with heart failure diagnosis
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Only female patients aged 79–89
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime
    -- Only first admission per patient
    AND a.admittime = (
      SELECT MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = p.subject_id
    )
    -- Only if first admission has heart failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN heart_failure_codes hfc
        ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
)
SELECT
  quantiles[OFFSET(2)] - quantiles[OFFSET(0)] AS los_iqr_days,
  quantiles[OFFSET(0)] AS los_25th_percentile,
  quantiles[OFFSET(2)] AS los_75th_percentile
FROM (
  SELECT
    APPROX_QUANTILES(los, 4) AS quantiles
  FROM hf_first_admissions
);