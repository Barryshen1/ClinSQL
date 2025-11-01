WITH pneumonia_copd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d1.icd_code = 'J18.9'  -- Pneumonia
    AND d2.icd_code = 'J44.9'  -- COPD
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS percentile_75_los_days
FROM
  pneumonia_copd_admissions
LIMIT 1;