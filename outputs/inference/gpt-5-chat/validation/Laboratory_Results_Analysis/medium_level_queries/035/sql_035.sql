WITH cohort AS (
  -- Step 1-4: Filter patients meeting demographic + ACS diagnosis + elevated initial troponin T
  WITH acs_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
      ON diag.icd_code = ddiag.icd_code 
     AND diag.icd_version = ddiag.icd_version
    WHERE pat.gender = 'M'
      AND pat.anchor_age BETWEEN 73 AND 83
      AND (
        LOWER(ddiag.long_title) LIKE '%acute myocardial infarction%' 
        OR LOWER(ddiag.long_title) LIKE '%unstable angina%' 
        OR LOWER(ddiag.long_title) LIKE '%acute ischemic heart%'
      )
  ),
  troponin_first AS (
    SELECT subject_id, hadm_id, MIN_BY(lab.valuenum, lab.charttime) AS first_trop_val, MIN(lab.charttime) AS first_trop_time
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
      ON lab.itemid = dl.itemid
    WHERE LOWER(dl.label) LIKE '%troponin t%'
      AND lab.valuenum IS NOT NULL
    GROUP BY subject_id, hadm_id
  )
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         t.first_trop_val, t.first_trop_time
  FROM acs_admissions a
  JOIN troponin_first t
    ON a.subject_id = t.subject_id
   AND a.hadm_id = t.hadm_id
  WHERE t.first_trop_val > 0.014  -- elevated cut-off
)
-- Step 7: Summarize
SELECT 
  COUNT(*) AS n_admissions,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS avg_los_days,
  100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate_percent
FROM cohort;