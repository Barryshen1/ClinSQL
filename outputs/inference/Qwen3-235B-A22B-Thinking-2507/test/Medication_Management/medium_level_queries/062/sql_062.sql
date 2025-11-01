WITH eligible_patients AS (
  -- Identify patients meeting demographic and diagnosis criteria
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
    AND EXISTS (
      -- Diabetes diagnosis (ICD-9: 250.x, ICD-10: E08-E13)
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR 
                                      d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR 
                                      d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%'))
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis (ICD-9: 428.x, ICD-10: I50.x)
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

glp1_medications AS (
  -- Identify GLP-1 receptor agonist prescriptions
  SELECT 
    p.hadm_id,
    p.starttime AS dose_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    -- Filter for GLP-1 RAs using drug names and brand names
    (LOWER(p.drug) LIKE '%liraglutide%' 
     OR LOWER(p.drug) LIKE '%victoza%'
     OR LOWER(p.drug) LIKE '%semaglutide%' 
     OR LOWER(p.drug) LIKE '%ozempic%'
     OR LOWER(p.drug) LIKE '%dulaglutide%' 
     OR LOWER(p.drug) LIKE '%trulicity%'
     OR LOWER(p.drug) LIKE '%exenatide%' 
     OR LOWER(p.drug) LIKE '%byetta%'
     OR LOWER(p.drug) LIKE '%lixisenatide%' 
     OR LOWER(p.drug) LIKE '%adlyxin%')
    -- Exclude oral routes
    AND p.route IS NOT NULL
    AND LOWER(p.route) NOT LIKE '%oral%'
    AND LOWER(p.route) NOT LIKE '%po%'
),

first_doses AS (
  -- Get first dose time for each admission
  SELECT 
    hadm_id,
    MIN(dose_time) AS first_dose_time
  FROM glp1_medications
  GROUP BY hadm_id
),

cohort_analysis AS (
  -- Combine population with first dose information
  SELECT 
    ep.hadm_id,
    ep.admittime,
    ep.dischtime,
    fd.first_dose_time,
    -- Flag if initiated in first 72h
    CASE 
      WHEN fd.first_dose_time <= TIMESTAMP_ADD(ep.admittime, INTERVAL 72 HOUR) THEN 1 
      ELSE 0 
    END AS initiated_in_first_72h,
    -- Flag if initiated in final 72h
    CASE 
      WHEN fd.first_dose_time >= TIMESTAMP_SUB(ep.dischtime, INTERVAL 72 HOUR) THEN 1 
      ELSE 0 
    END AS initiated_in_last_72h
  FROM eligible_patients ep
  LEFT JOIN first_doses fd ON ep.hadm_id = fd.hadm_id
)

-- Final calculation of rates and changes
SELECT 
  COUNT(*) AS total_patients,
  SUM(initiated_in_first_72h) AS count_first_72h,
  SUM(initiated_in_last_72h) AS count_last_72h,
  ROUND(SUM(initiated_in_first_72h) * 100.0 / COUNT(*), 2) AS rate_first_72h_percent,
  ROUND(SUM(initiated_in_last_72h) * 100.0 / COUNT(*), 2) AS rate_last_72h_percent,
  ROUND((SUM(initiated_in_last_72h) * 1.0 / COUNT(*) - SUM(initiated_in_first_72h) * 1.0 / COUNT(*)) * 100, 2) AS absolute_change_percent,
  CASE 
    WHEN SUM(initiated_in_first_72h) = 0 THEN NULL
    ELSE ROUND(((SUM(initiated_in_last_72h) * 1.0 / COUNT(*) - SUM(initiated_in_first_72h) * 1.0 / COUNT(*)) / (SUM(initiated_in_first_72h) * 1.0 / COUNT(*))) * 100, 2)
  END AS relative_change_percent
FROM cohort_analysis;