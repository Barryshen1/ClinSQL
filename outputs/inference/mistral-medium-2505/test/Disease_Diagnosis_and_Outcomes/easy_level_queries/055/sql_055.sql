WITH
-- Filter for male patients aged 37-47
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
),

-- Get admissions with primary AKI diagnosis
aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p
    ON a.subject_id = p.subject_id
  WHERE
    d.seq_num = 1  -- Primary diagnosis
    AND d.icd_code LIKE 'N17.%'  -- AKI ICD-10 codes
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

-- Calculate 75th percentile LOS
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75_los_days
FROM
  aki_admissions;