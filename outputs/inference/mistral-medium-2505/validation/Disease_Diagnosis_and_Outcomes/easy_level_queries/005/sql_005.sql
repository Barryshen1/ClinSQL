WITH ischemic_stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND d.icd_code LIKE 'I63%'  -- Ischemic stroke ICD-10 codes
    AND d.seq_num = 1  -- Primary diagnosis
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

SELECT
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median_los_days
FROM
  ischemic_stroke_admissions
LIMIT 1;