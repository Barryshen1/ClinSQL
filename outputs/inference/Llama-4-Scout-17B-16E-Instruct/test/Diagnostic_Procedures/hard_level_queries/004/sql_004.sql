WITH 
  -- Target population: Female ICU patients aged 50–60 with intracranial hemorrhage
  target_population AS (
    SELECT 
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      p.anchor_age,
      p.gender,
      ic.intime,
      ic.outtime,
      ic.los,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ic.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 50 AND 60
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE '907.%'  -- Intracranial hemorrhage ICD-9 codes
      )
  ),
  
  -- Procedure burden during the first 72 ICU hours
  procedure_burden AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      COUNT(*) AS procedure_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE 
      charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)
    GROUP BY 
      subject_id, hadm_id, stay_id
  ),
  
  -- Merge target population with procedure burden
  merged_data AS (
    SELECT 
      tp.subject_id,
      tp.hadm_id,
      tp.stay_id,
      tp.intime,
      tp.outtime,
      tp.los,
      tp.hospital_expire_flag,
      COALESCE(pb.procedure_count, 0) AS procedure_count
    FROM 
      target_population tp
    LEFT JOIN 
      procedure_burden pb 
        ON tp.subject_id = pb.subject_id AND tp.hadm_id = pb.hadm_id AND tp.stay_id = pb.stay_id
  )

-- Calculate percentiles of procedure burden and compare ICU LOS and in-hospital mortality
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY procedure_count) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY procedure_count) AS median,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY procedure_count) AS p90,
  AVG(los) AS avg_icu_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
FROM 
  merged_data;