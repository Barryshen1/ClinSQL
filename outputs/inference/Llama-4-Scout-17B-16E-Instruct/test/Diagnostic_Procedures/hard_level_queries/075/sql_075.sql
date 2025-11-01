WITH 
  -- Identify patients with DKA
  dka_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE 
      a.admission_type = 'Emergency'  
      AND d.icd_code LIKE '%250.1%'  
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 39 AND 49
  ),

  -- ICU stay information
  icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.intime, 
      i.outtime, 
      i.los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      dka_patients dp ON i.subject_id = dp.subject_id AND i.hadm_id = dp.hadm_id
  ),

  -- Procedures in the first 24 hours
  procedures_first_24h AS (
    SELECT 
      stay_id, 
      COUNT(DISTINCT itemid) AS procedure_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE 
      stay_id IN (SELECT stay_id FROM icu_stays)
      AND starttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
    GROUP BY 
      stay_id
  ),

  -- Calculate quintiles of procedure counts
  quintiles AS (
    SELECT 
      NTILE(5) OVER (ORDER BY procedure_count) AS quintile,
      procedure_count,
      stay_id
    FROM 
      procedures_first_24h
  ),

  -- Join with ICU stays for LOS and mortality
  final_data AS (
    SELECT 
      q.quintile,
      q.procedure_count,
      icu_stay.stay_id,
      icu_stay.los,
      CASE 
        WHEN a.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END AS hospital_mortality
    FROM 
      quintiles q
    JOIN 
      icu_stays icu_stay ON q.stay_id = icu_stay.stay_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu_stay.hadm_id = a.hadm_id
  )

-- Final aggregation
SELECT 
  quintile,
  COUNT(stay_id) AS number_of_stays,
  AVG(procedure_count) AS mean_procedure_count,
  MIN(procedure_count) AS min_procedure_count,
  MAX(procedure_count) AS max_procedure_count,
  AVG(los) AS mean_icu_los,
  AVG(hospital_mortality) * 100 AS hospital_mortality_percentage
FROM 
  final_data
GROUP BY 
  quintile
ORDER BY 
  quintile;