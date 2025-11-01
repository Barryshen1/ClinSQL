WITH lower_gi_bleeding AS (
  SELECT 
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1  -- principal diagnosis
    AND (
      (di.icd_version = 9 AND di.icd_code IN ('569.84', '569.85', '569.86', '569.87', '569.89'))
      OR 
      (di.icd_version = 10 AND di.icd_code IN (
        'K5521', 'K5522', 
        'K5700', 'K5701', 'K5702', 'K5703', 
        'K5710', 'K5711', 'K5712', 'K5713', 
        'K5720', 'K5721', 'K5722', 'K5723', 
        'K5730', 'K5731', 'K5732', 'K5733', 
        'K5740', 'K5741', 'K5742', 'K5743', 
        'K5750', 'K5751', 'K5752', 'K5753', 
        'K5780', 'K5781', 'K5782', 'K5783', 
        'K5790', 'K5791', 'K5792', 'K5793', 
        'K620', 'K625', 'K626', 'K635'
      ))
    )
),
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN lower_gi_bleeding lgb 
    ON a.hadm_id = lgb.hadm_id
  WHERE 
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location IN ('EMERGENCY ROOM ADMIT', 'TRANSFER FROM HOSPITAL EMERGENCY ROOM')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),
readmission_status AS (
  SELECT 
    tp.*,
    LEAD(tp.admittime) OVER (PARTITION BY tp.subject_id ORDER BY tp.admittime) AS next_admittime,
    CASE 
      WHEN LEAD(tp.admittime) OVER (PARTITION BY tp.subject_id ORDER BY tp.admittime) 
        BETWEEN tp.dischtime AND DATETIME_ADD(tp.dischtime, INTERVAL 30 DAY) 
        THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM target_population tp
)
SELECT 
  -- 30-day readmission rate
  SUM(readmitted_30d) / COUNT(*) AS readmission_rate,
  -- Median LOS for readmitted patients
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  -- Median LOS for non-readmitted patients
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- Percent with LOS > 6 days (overall)
  SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_gt_6_days
FROM readmission_status;