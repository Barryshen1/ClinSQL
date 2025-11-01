WITH pneu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
    -- Heuristic for community-acquired: emergency admission and not a transfer
    AND a.admission_type = 'EMERGENCY'
    AND NOT LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
    -- Ensure valid times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
)
SELECT
  -- Approximate 25th percentile of LOS (days)
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_days_p25,
  COUNT(*) AS n_admissions
FROM pneu_admissions;