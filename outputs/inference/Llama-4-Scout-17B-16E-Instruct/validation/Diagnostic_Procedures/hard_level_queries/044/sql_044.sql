WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      i.stay_id,
      p.anchor_age,
      a.admittime,
      a.deathtime,
      a.hospital_expire_flag,
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
    WHERE 
      p.anchor_age BETWEEN 82 AND 92
      AND p.gender = 'M'
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
        AND d.icd_code IN ('785.52', 'I05.1', 'I06.1', 'I07.1', 'I09.1', 'I11.1', 'I13.1', 'I24.1', 'I25.1', 'I27.1', 'I33.1', 'I40.1', 'I41.1', 'I42.1', 'I43.1', 'I44.1', 'I45.1', 'I46.1', 'I47.1', 'I48.1', 'I49.1', 'I50.1', 'I51.1', 'I52.1')
      )
  ),
  
  -- Calculate procedure burden in the first 24 hours
  procedure_burden AS (
    SELECT 
      pe.subject_id, 
      pe.hadm_id, 
      pe.stay_id,
      COUNT(*) as procedure_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN 
      patients_of_interest poi 
      ON pe.hadm_id = poi.hadm_id AND pe.stay_id = poi.stay_id
    WHERE 
      pe.starttime < DATETIME_ADD(poi.admittime, INTERVAL 1 DAY)
    GROUP BY 
      pe.subject_id, 
      pe.hadm_id, 
      pe.stay_id
  ),
  
  -- Merge with hospital outcomes
  outcomes AS (
    SELECT 
      p.subject_id, 
      p.hadm_id, 
      p.stay_id,
      p.procedure_count,
      poi.hospital_expire_flag,
      poi.dischtime,
      poi.admittime
    FROM 
      procedure_burden p
    JOIN 
      patients_of_interest poi 
      ON p.hadm_id = poi.hadm_id
  ),
  
  -- Calculate quintiles
  quintiles AS (
    SELECT 
      procedure_count,
      hospital_expire_flag,
      dischtime,
      admittime,
      NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM 
      outcomes
  )

-- Stratify into quintiles and calculate statistics
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_hospital_LOS,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS in_hospital_mortality_percentage
FROM 
  quintiles
GROUP BY 
  quintile
ORDER BY 
  quintile;