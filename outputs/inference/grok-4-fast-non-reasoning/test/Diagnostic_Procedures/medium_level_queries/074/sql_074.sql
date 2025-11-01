WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS total_hosp_los_hr,
    COALESCE(SUM(CASE 
      WHEN tr.eventtype = 2  -- discharge
        AND tr.careunit LIKE 'ICU%' 
        AND tr.outtime IS NOT NULL
      THEN TIMESTAMP_DIFF(tr.outtime, tr.intime, HOUR) 
      ELSE 0 
    END), 0) AS total_icu_los_hr
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.transfers` tr
    ON a.subject_id = tr.subject_id 
    AND a.hadm_id = tr.hadm_id
    AND tr.eventtype IN (1, 2)  -- 1=admit, 2=discharge
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
  HAVING total_hosp_los_hr BETWEEN 24 AND 168  -- 1-7 days in hours
),
imaging_counts AS (
  SELECT 
    fa.*,
    COUNT(DISTINCT CASE 
      WHEN pi.icd_version = '10' 
        AND REGEXP_CONTAINS(pi.icd_code, r'^(BW|BR|BQ|BP|BN|BM|BL|BK|BJ|BH|BG|BF|BE|BD|BC|BB|BA)')  -- ICD-10-PCS imaging (e.g., CT/MRI head/neck/vascular)
      THEN pi.icd_code 
    END) AS num_imaging_procedures
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fa.subject_id = pi.subject_id
    AND fa.hadm_id = pi.hadm_id
  GROUP BY fa.hadm_id, fa.subject_id, fa.admittime, fa.dischtime, fa.total_hosp_los_hr, fa.total_icu_los_hr
)
SELECT 
  CASE 
    WHEN total_icu_los_hr > 0 THEN 'With ICU' 
    ELSE 'Without ICU' 
  END AS icu_stratum,
  CASE 
    WHEN total_hosp_los_hr <= 96 THEN '1-4 days'  -- 4*24=96 hours
    WHEN total_hosp_los_hr > 96 THEN '5-7 days'
    ELSE 'Other'
  END AS hosp_los_bucket,
  AVG(num_imaging_procedures) AS mean_imaging,
  MIN(num_imaging_procedures) AS min_imaging,
  MAX(num_imaging_procedures) AS max_imaging,
  COUNT(*) AS num_admissions
FROM imaging_counts
GROUP BY icu_stratum, hosp_los_bucket
ORDER BY icu_stratum, 
  CASE hosp_los_bucket 
    WHEN '1-4 days' THEN 1 
    WHEN '5-7 days' THEN 2 
    ELSE 3 
  END;