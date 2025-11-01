WITH primary_pna_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
       AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
    AND LOWER(di.long_title) LIKE '%pneumonia%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    AND a.admission_type = 'EMERGENCY'  -- proxy for community-acquired presentation
)

SELECT
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM primary_pna_adms;