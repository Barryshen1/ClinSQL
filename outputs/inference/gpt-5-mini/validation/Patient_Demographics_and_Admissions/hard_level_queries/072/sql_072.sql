WITH principal_dx AS (
  -- admissions whose principal (seq_num=1) diagnosis is acute respiratory failure
  SELECT
    di.icd_code,
    di.icd_version,
    di.long_title,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND COALESCE(CAST(d.icd_version AS STRING), '') = COALESCE(CAST(di.icd_version AS STRING), '')
  WHERE
    d.seq_num = 1
    AND LOWER(di.long_title) LIKE '%respiratory failure%'
    AND LOWER(di.long_title) LIKE '%acute%'
),

index_admissions AS (
  -- Select index admissions meeting demographics/payer/admission-location criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender,
    -- LOS in days as fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    principal_dx pd
  ON
    a.hadm_id = pd.hadm_id
  WHERE
    -- demographics & payer & source
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    AND (
      LOWER(COALESCE(a.admission_location, '')) LIKE '%snf%'
      OR LOWER(COALESCE(a.admission_location, '')) LIKE '%skilled%'
    )
    -- must have times to compute LOS/readmission interval
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- exclude in-hospital deaths (cannot be readmitted)
    AND COALESCE(a.hospital_expire_flag, 0) = 0
),

index_with_readmit_flag AS (
  -- For each index admission, determine if there is any readmission within 30 days
  SELECT
    ia.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` r
        WHERE r.subject_id = ia.subject_id
          AND r.hadm_id != ia.hadm_id
          -- readmission after discharge
          AND r.admittime IS NOT NULL
          AND r.admittime > ia.dischtime
          -- within 30 days (<= 30 days)
          AND TIMESTAMP_DIFF(r.admittime, ia.dischtime, DAY) <= 30
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    index_admissions ia
)

SELECT
  COUNT(*) AS total_index_stays,
  SUM(readmitted_30d) AS readmitted_count_30d,
  SAFE_DIVIDE(SUM(readmitted_30d), COUNT(*)) AS readmission_rate_30d,
  -- median LOS by readmission status (approximate median)
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted_days,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted_days,
  -- percent index stays > 8 days overall
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END), COUNT(*)) AS pct_index_stays_gt_8_days_overall,
  -- percent >8 days by readmission status
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d = 1 AND los_days > 8 THEN 1 ELSE 0 END), NULLIF(SUM(CASE WHEN readmitted_30d = 1 THEN 1 ELSE 0 END),0)) AS pct_gt_8_days_when_readmitted,
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d = 0 AND los_days > 8 THEN 1 ELSE 0 END), NULLIF(SUM(CASE WHEN readmitted_30d = 0 THEN 1 ELSE 0 END),0)) AS pct_gt_8_days_when_not_readmitted
FROM
  index_with_readmit_flag;