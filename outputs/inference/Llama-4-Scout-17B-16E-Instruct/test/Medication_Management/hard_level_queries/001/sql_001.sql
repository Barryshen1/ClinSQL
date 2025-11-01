WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 76 AND 86
      AND p.gender = 'F'
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND d.icd_code IN ('I46.9', 'I46.0', 'I46.1', 'I46.2', 'I46.8', 'I46.9')
      )
  ),
  
  -- Calculate medication complexity
  medication_complexity AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      COUNT(DISTINCT p.drug) AS medication_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN 
      patients_of_interest poi 
        ON p.subject_id = poi.subject_id AND p.hadm_id = poi.hadm_id
    WHERE 
      p.starttime BETWEEN TIMESTAMP_SUB(poi.admittime, INTERVAL 7 DAY) AND poi.admittime
    GROUP BY 
      p.subject_id, p.hadm_id
  ),
  
  -- Assign quintiles
  quintiles AS (
    SELECT 
      poi.*,
      mc.medication_count,
      NTILE(5) OVER (ORDER BY mc.medication_count) AS quintile
    FROM 
      patients_of_interest poi
    JOIN 
      medication_complexity mc 
        ON poi.subject_id = mc.subject_id AND poi.hadm_id = mc.hadm_id
  ),
  
  -- Calculate LOS, mortality, readmission
  outcomes AS (
    SELECT 
      q.quintile,
      COUNT(DISTINCT q.hadm_id) AS patient_count,
      AVG(q.medication_count) AS avg_score,
      MIN(q.medication_count) AS min_score,
      MAX(q.medication_count) AS max_score,
      AVG(DATE_DIFF(q.dischtime, q.admittime)) AS los,
      SUM(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS mortality_rate,
      -- Simplified 30-day readmission calculation, actual implementation may vary based on data availability
      0 AS readmission_rate  -- Placeholder, actual calculation needed
    FROM 
      quintiles q
    GROUP BY 
      q.quintile
  )

SELECT 
  quintile,
  patient_count,
  avg_score,
  min_score,
  max_score,
  los,
  mortality_rate * 100 AS mortality_percentage,
  readmission_rate * 100 AS readmission_percentage
FROM 
  outcomes
ORDER BY 
  quintile;