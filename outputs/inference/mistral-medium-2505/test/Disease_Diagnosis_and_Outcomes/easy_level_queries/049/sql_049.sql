WITH stroke_admissions AS (
  -- Get admissions for women aged 50-60 with primary ischemic stroke
  SELECT
    a.hadm_id,
    a.subject_id,
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
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-10 codes for ischemic stroke (I63.*)
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
      OR
      -- ICD-9 codes for ischemic stroke (434.*)
      (d.icd_version = 9 AND d.icd_code LIKE '434%')
    )
    AND a.dischtime IS NOT NULL
)

-- Calculate the 25th percentile of hospital LOS
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS percentile_25_los
FROM
  stroke_admissions
LIMIT 1;