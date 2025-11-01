WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (dd.long_title LIKE '%diabetes%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (dd.long_title LIKE '%heart failure%' OR d.icd_code LIKE 'I50%' OR d.icd_code LIKE 'I11%' OR d.icd_code LIKE 'I13%')
    )
),
med_windows AS (
  SELECT 
    c.hadm_id,
    -- Insulin in first 12 hours
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR
        AND (LOWER(p.drug) LIKE '%insulin%')
    ) THEN 1 ELSE 0 END AS insulin_first12h,
    -- Oral agents in first 12 hours
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR
        AND (
          LOWER(p.drug) LIKE '%metformin%' OR
          LOWER(p.drug) LIKE '%glipizide%' OR
          LOWER(p.drug) LIKE '%glyburide%' OR
          LOWER(p.drug) LIKE '%pioglitazone%' OR
          LOWER(p.drug) LIKE '%rosiglitazone%' OR
          LOWER(p.drug) LIKE '%sitagliptin%' OR
          LOWER(p.drug) LIKE '%linagliptin%' OR
          LOWER(p.drug) LIKE '%empagliflozin%' OR
          LOWER(p.drug) LIKE '%dapagliflozin%' OR
          LOWER(p.drug) LIKE '%canagliflozin%' OR
          LOWER(p.drug) LIKE '%saxagliptin%' OR
          LOWER(p.drug) LIKE '%alogliptin%' OR
          LOWER(p.drug) LIKE '%vildagliptin%' OR
          LOWER(p.drug) LIKE '%repaglinide%' OR
          LOWER(p.drug) LIKE '%nateglinide%'
        )
    ) THEN 1 ELSE 0 END AS oral_first12h,
    -- Insulin in final 48 hours
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime
        AND (LOWER(p.drug) LIKE '%insulin%')
    ) THEN 1 ELSE 0 END AS insulin_final48h,
    -- Oral agents in final 48 hours
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime
        AND (
          LOWER(p.drug) LIKE '%metformin%' OR
          LOWER(p.drug) LIKE '%glipizide%' OR
          LOWER(p.drug) LIKE '%glyburide%' OR
          LOWER(p.drug) LIKE '%pioglitazone%' OR
          LOWER(p.drug) LIKE '%rosiglitazone%' OR
          LOWER(p.drug) LIKE '%sitagliptin%' OR
          LOWER(p.drug) LIKE '%linagliptin%' OR
          LOWER(p.drug) LIKE '%empagliflozin%' OR
          LOWER(p.drug) LIKE '%dapagliflozin%' OR
          LOWER(p.drug) LIKE '%canagliflozin%' OR
          LOWER(p.drug) LIKE '%saxagliptin%' OR
          LOWER(p.drug) LIKE '%alogliptin%' OR
          LOWER(p.drug) LIKE '%vildagliptin%' OR
          LOWER(p.drug) LIKE '%repaglinide%' OR
          LOWER(p.drug) LIKE '%nateglinide%'
        )
    ) THEN 1 ELSE 0 END AS oral_final48h
  FROM cohort c
)
SELECT 
  'insulin' AS medication,
  AVG(insulin_first12h) AS prevalence_first12h,
  AVG(insulin_final48h) AS prevalence_final48h,
  AVG(insulin_final48h) - AVG(insulin_first12h) AS net_change
FROM med_windows
UNION ALL
SELECT 
  'oral agent' AS medication,
  AVG(oral_first12h) AS prevalence_first12h,
  AVG(oral_final48h) AS prevalence_final48h,
  AVG(oral_final48h) - AVG(oral_first12h) AS net_change
FROM med_windows;