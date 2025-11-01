WITH
  -- 1) Filter to male patients aged 87-97
  patient_filter AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'Male'
      AND anchor_age BETWEEN 87 AND 97
  ),

  -- 2) Admissions with computed length of stay
  admissions_age AS (
    SELECT a.hadm_id,
           a.subject_id,
           a.admittime,
           a.dischtime,
           TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS length_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patient_filter pf ON a.subject_id = pf.subject_id
    -- Note: dischtime is expected to be non-null for complete admissions
    WHERE a.dischtime IS NOT NULL
  ),

  -- 3) Sepsis flags per admission (has_sepsis, has_septic_shock)
  sepsis_flags AS (
    SELECT aa.hadm_id,
           MAX(CASE WHEN dd.long_title LIKE '%sepsis%' THEN 1 ELSE 0 END) AS has_sepsis,
           MAX(CASE WHEN dd.long_title LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock
    FROM admissions_age aa
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON aa.subject_id = di.subject_id
     AND aa.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    GROUP BY aa.hadm_id
  ),

  -- 4) Admissions with sepsis and no septic shock
  admissions_with_sepsis AS (
    SELECT aa.hadm_id,
           aa.subject_id,
           aa.admittime,
           aa.dischtime,
           aa.length_days
    FROM admissions_age aa
    JOIN sepsis_flags sf
      ON aa.hadm_id = sf.hadm_id
    WHERE sf.has_sepsis = 1
      AND sf.has_septic_shock = 0
  ),

  -- 5) Diagnostic procedure counts per admission
  diagnostic_counts AS (
    SELECT a.hadm_id,
           COUNT(dp.icd_code) AS diag_proc_count
    FROM admissions_with_sepsis a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
       ON a.subject_id = pc.subject_id
      AND a.hadm_id = pc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
       ON pc.icd_code = dp.icd_code
      AND pc.icd_version = dp.icd_version
      AND (dp.long_title LIKE '%diagnostic%' 
           OR dp.long_title LIKE '%diagnosis%' 
           OR dp.long_title LIKE '%diagnostic procedure%')
    GROUP BY a.hadm_id
  )

SELECT
  CASE
    WHEN a.length_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN a.length_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS stay_bin,
  AVG(COALESCE(dc.diag_proc_count, 0)) AS mean_diagnostic_procedures
FROM admissions_with_sepsis a
LEFT JOIN diagnostic_counts dc
  ON a.hadm_id = dc.hadm_id
WHERE a.length_days BETWEEN 1 AND 7
GROUP BY stay_bin
ORDER BY stay_bin;