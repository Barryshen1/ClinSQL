WITH
-- Get female Medicare patients aged 76-86 transferred from another hospital
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id AS index_hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24 AS index_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM HOSP/EXTRAM'
),

-- Get AMI admissions (principal diagnosis)
ami_admissions AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),

-- Combine to get eligible AMI patients
index_admissions AS (
  SELECT
    ep.subject_id,
    ep.index_hadm_id,
    ep.index_admittime,
    ep.index_dischtime,
    ep.index_los_days
  FROM
    eligible_patients ep
  JOIN
    ami_admissions aa
    ON ep.subject_id = aa.subject_id AND ep.index_hadm_id = aa.hadm_id
),

-- Find 30-day readmissions
readmissions AS (
  SELECT
    ia.subject_id,
    ia.index_hadm_id,
    ia.index_admittime,
    ia.index_dischtime,
    ia.index_los_days,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, ia.index_dischtime, DAY) AS days_to_readmit
  FROM
    index_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ia.subject_id = a.subject_id
  WHERE
    a.admittime > ia.index_dischtime
    AND TIMESTAMP_DIFF(a.admittime, ia.index_dischtime, DAY) <= 30
    AND a.hadm_id != ia.index_hadm_id  -- Exclude same admission
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    ia.subject_id,
    ia.index_hadm_id,
    ia.index_los_days,
    CASE WHEN r.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_30day_readmission
  FROM
    index_admissions ia
  LEFT JOIN
    readmissions r
    ON ia.subject_id = r.subject_id AND ia.index_hadm_id = r.index_hadm_id
)

-- Final results
SELECT
  -- 30-day readmission rate
  COUNT(CASE WHEN has_30day_readmission = 1 THEN 1 END) * 100.0 /
    COUNT(*) AS readmission_rate_percentage,

  -- Median LOS for readmitted vs not readmitted
  PERCENTILE_CONT(CASE WHEN has_30day_readmission = 1 THEN index_los_days END, 0.5)
    OVER() AS median_los_readmitted,
  PERCENTILE_CONT(CASE WHEN has_30day_readmission = 0 THEN index_los_days END, 0.5)
    OVER() AS median_los_not_readmitted,

  -- Percent of index stays >4 days
  COUNT(CASE WHEN index_los_days > 4 THEN 1 END) * 100.0 / COUNT(*) AS percent_stays_gt_4days

FROM
  readmission_flags
GROUP BY
  subject_id, index_hadm_id, index_los_days, has_30day_readmission
LIMIT 1;