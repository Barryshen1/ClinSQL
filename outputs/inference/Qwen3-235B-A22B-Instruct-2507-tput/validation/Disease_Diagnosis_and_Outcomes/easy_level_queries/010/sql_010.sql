WITH patient_los AS (
  SELECT
    a.hadm_id,
    p.gender,
    -- Calculate age at admission
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admit,
    -- Calculate hospital LOS in days as a decimal
    DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) / (24 * 60.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON
    a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON
    diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'F'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND LOWER(d_diag.long_title) LIKE '%chronic obstructive%'
    AND LOWER(d_diag.long_title) LIKE '%exacerbat%'
    -- Ensure valid admission/discharge times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM
  patient_los
WHERE
  age_at_admit >= 49
  AND age_at_admit <= 59;