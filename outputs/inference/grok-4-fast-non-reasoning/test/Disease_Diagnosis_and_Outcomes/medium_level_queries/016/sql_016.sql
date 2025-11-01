WITH patient_filter AS (
  -- Filter patients: males aged 40-50
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 40 AND 50
),
ami_admissions AS (
  -- Get admissions with primary AMI diagnosis, excluding shock/respiratory failure
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_filter p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  -- Primary AMI (ICD-10)
  WHERE d.seq_num = 1 
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I21%'
    AND DATE(a.dischtime) > DATE(a.admittime)  -- Valid discharge
  -- Exclude shock or respiratory failure in any diagnosis
  AND NOT EXISTS (
    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    WHERE d2.subject_id = a.subject_id 
      AND d2.hadm_id = a.hadm_id 
      AND d2.icd_version = 10
      AND (
        d2.icd_code = 'R57.0'  -- Cardiogenic shock
        OR d2.icd_code LIKE 'R57%'  -- Other shock
        OR d2.icd_code LIKE 'J96.0%'  -- Acute resp failure
        OR d2.icd_code LIKE 'J96.2%'  -- Acute resp failure
      )
  )
  -- One admission per patient (earliest)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
icu_cohort AS (
  -- Add day-1 ICU status for patients with ICU stay on admission day
  SELECT 
    aa.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 'Y' ELSE 'N' END AS day1_icu_status
  FROM ami_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON aa.subject_id = i.subject_id 
    AND aa.hadm_id = i.hadm_id
    AND DATE(i.intime) = DATE(aa.admittime)  -- Day-1 stay
  QUALIFY ROW_NUMBER() OVER (PARTITION BY aa.subject_id, aa.hadm_id ORDER BY i.intime NULLS LAST) = 1  -- First ICU stay if applicable, preserve non-ICU
),
grouped_data AS (
  SELECT 
    CASE 
      WHEN los_days <= 5 THEN '<=5'
      ELSE '>5'
    END AS los_group,
    day1_icu_status,
    hospital_expire_flag,
    los_days,
    COUNT(*) OVER (PARTITION BY 
      CASE WHEN los_days <= 5 THEN '<=5' ELSE '>5' END, 
      day1_icu_status
    ) AS group_size
  FROM icu_cohort
)
SELECT 
  los_group,
  day1_icu_status,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag) * 100.0, COUNT(*)), 2) AS mortality_pct,
  -- Median LOS using PERCENTILE_CONT for accuracy
  PERCENTILE_CONT(los_days, 0.5) AS median_los_days
FROM grouped_data
GROUP BY los_group, day1_icu_status
ORDER BY los_group, day1_icu_status;