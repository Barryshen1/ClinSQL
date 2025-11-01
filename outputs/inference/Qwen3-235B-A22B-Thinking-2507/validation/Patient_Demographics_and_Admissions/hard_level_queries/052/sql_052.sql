WITH index_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm,
    -- Compute LOS in days (as float)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND a.admission_location LIKE '%EMERGENCY%'
    AND a.insurance = 'Medicare'
    AND d.seq_num = 1  -- primary diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('5770','5771'))
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
    )
),
filtered_index AS (
  SELECT 
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    los_days,
    -- Check for readmission within 30 days
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = index_admissions.subject_id
          AND a2.admittime > index_admissions.dischtime
          AND a2.admittime <= index_admissions.dischtime + INTERVAL '30' DAY
          AND a2.hadm_id != index_admissions.hadm_id
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions
  WHERE age_at_adm BETWEEN 51 AND 61
)
SELECT
  COUNT(*) AS total_index,
  SUM(readmitted_30d) AS readmitted_count,
  SAFE_DIVIDE(SUM(readmitted_30d), COUNT(*)) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_nonreadmitted,
  (COUNTIF(los_days > 9) * 100.0) / COUNT(*) AS percent_gt9
FROM filtered_index;