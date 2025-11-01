WITH 
-- Identify patients with ADHF and relevant comorbidities
admissions_criteria AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(a.dischtime, TIMESTAMP_CURRENT) AS dischtime_or_current,
    TIMESTAMP_DIFF(COALESCE(a.dischtime, TIMESTAMP_CURRENT), a.admittime, DAY) AS los,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` didx 
        ON dicd.icd_code = didx.icd_code 
        AND dicd.icd_version = didx.icd_version
      WHERE 
        (didx.long_title LIKE '%Acute and chronic systolic heart failure%'
         OR didx.long_title LIKE '%Acute systolic heart failure%'
         OR didx.long_title LIKE '%Chronic systolic heart failure%')
        AND dicd.hadm_id = a.hadm_id
    ) AS has_adhf,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` didx 
        ON dicd.icd_code = didx.icd_code 
        AND dicd.icd_version = didx.icd_version
      WHERE 
        didx.long_title LIKE '%Chronic kidney disease%'
        AND dicd.hadm_id = a.hadm_id
    ) AS has_ckd,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` didx 
        ON dicd.icd_code = didx.icd_code 
        AND dicd.icd_version = didx.icd_version
      WHERE 
        didx.long_title LIKE '%Diabetes mellitus%'
        AND dicd.hadm_id = a.hadm_id
    ) AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` didx 
        ON dicd.icd_code = didx.icd_code 
        AND dicd.icd_version = didx.icd_version
      WHERE 
        (didx.long_title LIKE '%Acute and chronic systolic heart failure%'
         OR didx.long_title LIKE '%Acute systolic heart failure%'
         OR didx.long_title LIKE '%Chronic systolic heart failure%')
        AND dicd.hadm_id = a.hadm_id
    )
),

icu_stay AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN stay_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS had_icu_stay
  FROM 
    admissions_criteria
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` 
      ON admissions_criteria.hadm_id = icustays.hadm_id
  GROUP BY 
    hadm_id
)

-- Final calculation
SELECT 
  CASE 
    WHEN los <= 7 THEN '≤7'
    ELSE '>7'
  END AS los_category,
  had_icu_stay,
  COUNT(DISTINCT CASE 
    WHEN hospital_expire_flag = 1 THEN hadm_id 
    END) AS num_deaths,
  COUNT(DISTINCT hadm_id) AS total_patients,
  SUM(CAST(has_ckd AS INT64)) AS num_ckd,
  SUM(CAST(has_diabetes AS INT64)) AS num_diabetes
FROM 
  admissions_criteria
JOIN 
  icu_stay 
    ON admissions_criteria.hadm_id = icu_stay.hadm_id
GROUP BY 
  1, 2;