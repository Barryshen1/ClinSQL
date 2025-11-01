WITH septic_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND d.icd_code = 'R652'  -- Septic shock
),
admission_procedures AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status,
    COUNT(hc.hcpcs_cd) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN septic_patients sp ON a.subject_id = sp.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents hc ON a.hadm_id = hc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d_h ON hc.hcpcs_cd = d_h.code
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  WHERE LOWER(d_h.short_description) LIKE '%echo%' 
     OR LOWER(d_h.short_description) LIKE '%ultrasound%'
     OR hc.hcpcs_cd IN ('76999', '93306', '93307', '93308', '93312', '93313', '93314', '93315', '93317', '93318', '93320', '93321', '93325', '93350', '93351')
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, i.stay_id
),
los_groups AS (
  SELECT 
    hadm_id,
    icu_status,
    ultrasound_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group
  FROM admission_procedures
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  icu_status,
  APPROX_QUANTILES(ultrasound_count, 1000)[OFFSET(250)] AS p25_ultrasounds,
  APPROX_QUANTILES(ultrasound_count, 1000)[OFFSET(500)] AS p50_ultrasounds,
  APPROX_QUANTILES(ultrasound_count, 1000)[OFFSET(750)] AS p75_ultrasounds,
  COUNT(*) AS admission_count
FROM los_groups
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;