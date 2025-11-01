WITH aki_patients AS (
  -- Get patients with primary AKI diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- Male patients aged 81-91
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    -- Primary diagnosis (seq_num = 1) with AKI-related ICD codes
    AND d.seq_num = 1
    AND (
      -- ICD-10 codes for AKI (N17.*)
      (d.icd_version = 10 AND di.icd_code LIKE 'N17%')
      OR
      -- ICD-9 codes for AKI (584.*)
      (d.icd_version = 9 AND di.icd_code LIKE '584%')
    )
    -- Valid discharge time and positive LOS
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) > 0
)

-- Calculate IQR for hospital LOS
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median,
  PERCENTILE_CONT(los_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr
FROM
  aki_patients
LIMIT 1;