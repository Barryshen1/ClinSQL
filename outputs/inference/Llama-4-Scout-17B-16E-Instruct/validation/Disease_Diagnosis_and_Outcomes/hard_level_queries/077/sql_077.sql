WITH 
-- Identify cohort
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    p.gender,
    p.dod,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '481%'  -- Pneumonia ICD code
    )
),

-- Identify AKI and ARDS
conditions AS (
  SELECT 
    hadm_id,
    subject_id,
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = hadm_id
        AND d.icd_code LIKE '584%'  -- AKI ICD code
      ), 1, 0
    ) AS has_AKI,
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = hadm_id
        AND d.icd_code LIKE '518.8%'  -- ARDS ICD code
      ), 1, 0
    ) AS has_ARDS
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY 
    hadm_id, subject_id
)

-- Final calculation
SELECT 
  COUNT(DISTINCT c.subject_id) AS cohort_size,
  APPROX_QUANTILES(EXTRACT(DAY FROM (c.dod - c.admittime)), 5) AS survival_days_distribution,
  SUM(IF(c.hospital_expire_flag = 1, 1, 0)) / COUNT(DISTINCT c.subject_id) AS in_hospital_mortality_rate,
  AVG(cond.has_AKI) AS AKI_rate,
  AVG(cond.has_ARDS) AS ARDS_rate
FROM 
  cohort c
JOIN 
  conditions cond ON c.hadm_id = cond.hadm_id;