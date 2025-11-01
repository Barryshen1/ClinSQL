WITH index_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Correct age calculation: age at current admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    CASE 
      WHEN adm.dischtime > TIMESTAMP_ADD(adm.admittime, INTERVAL 4 DAY) THEN 1 
      ELSE 0 
    END AS los_gt_4
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('430','431','4320','4321','4329'))
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
    )
    AND adm.hospital_expire_flag = 0
),
filtered_index AS (
  SELECT *
  FROM index_admissions
  WHERE age_at_admission BETWEEN 68 AND 78
),
readmission_flag AS (
  SELECT 
    fi.subject_id, 
    fi.hadm_id, 
    fi.los_days,
    fi.los_gt_4,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2
      WHERE 
        adm2.subject_id = fi.subject_id
        AND adm2.hadm_id <> fi.hadm_id
        AND adm2.admittime > fi.dischtime
        AND adm2.admittime <= TIMESTAMP_ADD(fi.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmission_flag
  FROM filtered_index fi
),
stats AS (
  SELECT 
    COUNT(*) AS total_index_admissions,
    SUM(rf.readmission_flag) AS readmission_count,  -- Use alias to reference column
    SUM(rf.los_gt_4) AS los_gt_4_count             -- Use alias to reference column
  FROM readmission_flag rf  -- Alias CTE as 'rf'
)
SELECT 
  (readmission_count / total_index_admissions) * 100 AS readmission_rate,
  (SELECT APPROX_QUANTILE(rf2.los_days, 0.5) 
   FROM readmission_flag rf2 
   WHERE rf2.readmission_flag = 1) AS median_los_readmitted,  -- Alias CTE in subquery
  (SELECT APPROX_QUANTILE(rf3.los_days, 0.5) 
   FROM readmission_flag rf3 
   WHERE rf3.readmission_flag = 0) AS median_los_non_readmitted,  -- Alias CTE in subquery
  (los_gt_4_count / total_index_admissions) * 100 AS pct_los_gt_4
FROM stats;