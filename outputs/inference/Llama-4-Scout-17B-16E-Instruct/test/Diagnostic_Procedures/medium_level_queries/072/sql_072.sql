WITH 
  target_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,  -- Added subject_id here
      a.admission_type,
      a.admittime,
      COALESCE(a.dischtime, a.deathtime) AS dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 52 AND 62
  ),

  admissions_with_diagnosis AS (
    SELECT 
      ta.hadm_id,
      ta.subject_id,  -- Also added here for clarity, though not strictly necessary
      ta.admission_type,
      ta.admittime,
      ta.dischtime,
      ta.anchor_age,
      ta.gender
    FROM 
      target_admissions ta
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON 
      ta.hadm_id = di.hadm_id
      AND ta.subject_id = di.subject_id
    WHERE 
      di.icd_code LIKE '577.0' OR di.icd_code LIKE 'K85%'
  ),

  admission_procedures AS (
    SELECT 
      hadm_id,
      COUNT(*) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY 
      hadm_id
  ),

  admission_los AS (
    SELECT 
      hadm_id,
      DATE_DIFF(COALESCE(dischtime, deathtime), admittime, DAY) AS los_days
    FROM 
      admissions_with_diagnosis
  ),

  combined_data AS (
    SELECT 
      ap.hadm_id,
      ap.num_procedures,
      al.los_days,
      CASE 
        WHEN awd.admission_type = 'Primary' THEN 'primary'
        ELSE 'secondary'
      END AS admission_category
    FROM 
      admission_procedures ap
    JOIN 
      admission_los al
    ON 
      ap.hadm_id = al.hadm_id
    JOIN 
      admissions_with_diagnosis awd
    ON 
      ap.hadm_id = awd.hadm_id
  )

SELECT 
  cd.admission_category,
  CASE 
    WHEN cd.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN cd.los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_category,
  AVG(cd.num_procedures) AS mean_procedures,
  MIN(cd.num_procedures) AS min_procedures,
  MAX(cd.num_procedures) AS max_procedures
FROM 
  combined_data cd
GROUP BY 
  cd.admission_category,
  CASE 
    WHEN cd.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN cd.los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END
ORDER BY 
  cd.admission_category,
  los_category;