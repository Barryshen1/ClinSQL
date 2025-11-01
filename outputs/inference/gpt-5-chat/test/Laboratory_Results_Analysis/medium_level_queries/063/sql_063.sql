WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.subject_id = dx.subject_id 
    AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND (
      -- ICD-9 ACS
      (dx.icd_version = 9 AND (
        dx.icd_code LIKE '410%' OR  -- AMI
        dx.icd_code IN ('4111','4118')  -- other ACS
      ))
      OR
      -- ICD-10 ACS
      (dx.icd_version = 10 AND (
        dx.icd_code LIKE 'I21%' OR  -- AMI STEMI/NSTEMI
        dx.icd_code LIKE 'I22%' OR  -- subsequent AMI
        dx.icd_code = 'I200'        -- unstable angina
      ))
    )
),
troponin_first AS (
  SELECT le.subject_id, le.hadm_id,
         le.charttime,
         le.valuenum,
         CAST(le.ref_range_upper AS FLOAT64) AS ul_normal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
first_trop_per_adm AS (
  SELECT subject_id, hadm_id,
         valuenum, ul_normal
  FROM (
    SELECT tf.*,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_first tf
  )
  WHERE rn = 1
    AND valuenum > ul_normal
)
SELECT 
  COUNT(*) AS n_patients,
  AVG(valuenum) AS mean_troponin,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] 
    - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_troponin
FROM first_trop_per_adm f
JOIN acs_admissions a
  ON f.subject_id = a.subject_id
  AND f.hadm_id = a.hadm_id;