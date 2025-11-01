WITH
-- Get female Medicare patients aged 77-87 admitted from SNF
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND a.hospital_expire_flag = FALSE
),

-- Get principal diagnosis of acute respiratory failure
principal_diagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.seq_num,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    LOWER(di.long_title) LIKE '%acute respiratory failure%'
    AND d.seq_num = 1  -- Principal diagnosis
),

-- Combine patient and diagnosis info
index_admissions AS (
  SELECT
    ep.subject_id,
    ep.hadm_id AS index_hadm_id,
    ep.admittime AS index_admittime,
    ep.dischtime AS index_dischtime,
    pd.icd_code,
    pd.long_title AS principal_diagnosis,
    TIMESTAMP_DIFF(ep.dischtime, ep.admittime, DAY) AS index_los
  FROM
    eligible_patients ep
  JOIN
    principal_diagnosis pd
  ON
    ep.subject_id = pd.subject_id
    AND ep.hadm_id = pd.hadm_id
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT DISTINCT
    ia.subject_id,
    ia.index_hadm_id,
    ia.index_admittime,
    ia.index_dischtime,
    ia.index_los,
    ia.principal_diagnosis,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, ia.index_dischtime, DAY) AS days_to_readmit
  FROM
    index_admissions ia
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    ia.subject_id = a.subject_id
    AND a.admittime > ia.index_dischtime
    AND TIMESTAMP_DIFF(a.admittime, ia.index_dischtime, DAY) <= 30
    AND a.hadm_id != ia.index_hadm_id
),

-- Flag patients with readmissions
readmission_flags AS (
  SELECT
    ia.subject_id,
    ia.index_hadm_id,
    ia.index_admittime,
    ia.index_dischtime,
    ia.index_los,
    ia.principal_diagnosis,
    EXISTS (
      SELECT 1
      FROM readmissions r
      WHERE r.subject_id = ia.subject_id
      AND r.index_hadm_id = ia.index_hadm_id
    ) AS has_30day_readmission
  FROM
    index_admissions ia
)

-- Final results
SELECT
  -- Readmission rate
  COUNT(CASE WHEN has_30day_readmission THEN 1 END) AS num_readmitted,
  COUNT(*) AS total_index_admissions,
  ROUND(COUNT(CASE WHEN has_30day_readmission THEN 1 END) / COUNT(*) * 100, 2) AS readmission_rate_percent,

  -- Median LOS comparison
  APPROX_QUANTILES(CASE WHEN has_30day_readmission THEN index_los ELSE NULL END, 4)[OFFSET(2)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT has_30day_readmission THEN index_los ELSE NULL END, 4)[OFFSET(2)] AS median_los_not_readmitted,

  -- Percent stays >8 days
  ROUND(COUNT(CASE WHEN index_los > 8 THEN 1 END) / COUNT(*) * 100, 2) AS percent_stays_gt_8days
FROM
  readmission_flags;