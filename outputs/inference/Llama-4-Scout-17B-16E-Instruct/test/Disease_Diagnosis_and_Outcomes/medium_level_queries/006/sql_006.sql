WITH 
-- Define sepsis and septic shock
sepsis_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    icu.los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '995.91'  -- Sepsis
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '785.52'  -- Septic shock
    )
),

-- Identify CKD and diabetes
ckd_diabetes AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = hadm_id
        AND d.icd_code IN ('585', '585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9', '586')
      ) THEN 1
      ELSE 0
    END AS has_ckd,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = hadm_id
        AND d.icd_code IN ('250', '250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9')
      ) THEN 1
      ELSE 0
    END AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculate LOS and quartiles
los_quartiles AS (
  SELECT 
    subject_id,
    hadm_id,
    los,
    NTILE(4) OVER (ORDER BY los) AS los_quartile
  FROM (
    SELECT 
      s.subject_id,
      s.hadm_id,
      COALESCE(TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY), 
               TIMESTAMP_DIFF(s.deathtime, s.admittime, DAY)) AS los
    FROM 
      sepsis_patients s
  ) t
)

-- Final calculation
SELECT 
  lq.los_quartile,
  AVG(CASE WHEN s.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(CKD.has_ckd) AS ckd_prevalence,
  AVG(CKD.has_diabetes) AS diabetes_prevalence
FROM 
  los_quartiles lq
JOIN 
  sepsis_patients s ON lq.hadm_id = s.hadm_id
JOIN 
  ckd_diabetes CKD ON s.hadm_id = CKD.hadm_id
GROUP BY 
  lq.los_quartile
ORDER BY 
  lq.los_quartile;