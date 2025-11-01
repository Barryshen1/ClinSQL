WITH first_admission AS (
  SELECT 
      p.subject_id, 
      a.hadm_id
  FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 76 AND 86
  QUALIFY 
      ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
aspirin_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
      LOWER(drug) LIKE '%aspirin%' 
      OR LOWER(drug) LIKE '%asa %' 
      OR LOWER(drug) LIKE '%asa' 
      OR LOWER(drug) LIKE '%acetylsalicylic%'
),
p2y12_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
      LOWER(drug) LIKE '%clopidogrel%' 
      OR LOWER(drug) LIKE '%plavix%' 
      OR LOWER(drug) LIKE '%ticagrelor%' 
      OR LOWER(drug) LIKE '%brilinta%' 
      OR LOWER(drug) LIKE '%prasugrel%' 
      OR LOWER(drug) LIKE '%effient%'
),
dapt_admissions AS (
  SELECT 
      a.hadm_id
  FROM 
      aspirin_patients a
  INNER JOIN 
      p2y12_patients p 
      ON a.hadm_id = p.hadm_id
  WHERE 
      a.hadm_id IN (SELECT hadm_id FROM first_admission)
),
icu_los AS (
  SELECT 
      d.hadm_id,
      COALESCE(SUM(i.los), 0) AS total_icu_los_days
  FROM 
      dapt_admissions d
  LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON d.hadm_id = i.hadm_id
  GROUP BY 
      d.hadm_id
)
SELECT 
    ROUND(AVG(total_icu_los_days), 2) AS avg_icu_los_days
FROM 
    icu_los;