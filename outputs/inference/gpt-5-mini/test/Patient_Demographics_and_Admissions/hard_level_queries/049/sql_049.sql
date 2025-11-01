WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- precise LOS in fractional days using DATETIME arithmetic
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE
    d.seq_num = 1
    -- principal diagnosis text contains 'acute kidney injury'
    AND LOWER(COALESCE(dicd.long_title, '')) LIKE '%acute kidney injury%'
    -- female patients
    AND (p.gender = 'F' OR LOWER(p.gender) LIKE 'f%')
    -- age 61-71
    AND p.anchor_age BETWEEN 61 AND 71
    -- Medicare insurance
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    -- admitted from SNF (pragmatic match)
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%snf%'
    -- require timestamps
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

index_with_readmit AS (
  SELECT
    ia.*,
    -- flag if there exists a subsequent admission for same subject within 30 days after discharge
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS has_readmit_30d
  FROM index_admissions ia
)

SELECT
  COUNT(*) AS total_index_admissions,
  SUM(CASE WHEN has_readmit_30d THEN 1 ELSE 0 END) AS readmit_30d_count,
  SAFE_DIVIDE(SUM(CASE WHEN has_readmit_30d THEN 1 ELSE 0 END), COUNT(*)) AS readmit_30d_rate,
  -- median LOS among index admissions that were readmitted within 30 days
  APPROX_QUANTILES(CASE WHEN has_readmit_30d THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted_days,
  -- median LOS among index admissions that were NOT readmitted within 30 days
  APPROX_QUANTILES(CASE WHEN NOT has_readmit_30d THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted_days,
  -- percent of index stays with LOS > 6 days (overall)
  SAFE_MULTIPLY(100.0, SAFE_DIVIDE(SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END), COUNT(*))) AS pct_index_stays_gt_6_days
FROM index_with_readmit;