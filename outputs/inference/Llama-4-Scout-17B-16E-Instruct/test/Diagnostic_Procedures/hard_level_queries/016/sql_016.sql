WITH 
  -- Filter and prepare patient data
  patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' AND
      p.anchor_age BETWEEN 88 AND 98
  ),
  
  -- Prepare ICU stay data
  icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los,
      first_careunit,
      last_careunit
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE 
      first_careunit = last_careunit  -- First ICU stay
  ),
  
  -- Prepare procedure data
  procedures AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      starttime,
      endtime,
      itemid
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE 
      itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE category = 'DiagnosticProcedure'
      )
  ),
  
  -- Diagnose pneumonia
  pneumonia AS (
    SELECT 
      subject_id,
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    ON 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`.icd_code = `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`.icd_code
    AND 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`.icd_version = `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`.icd_version
    WHERE 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`.long_title LIKE '%Pneumonia%'
  ),
  
  -- Calculate procedure counts within first 72 hours of ICU stay
  procedure_counts AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      COUNT(DISTINCT pr.itemid) AS procedure_count
    FROM 
      patients p
    JOIN 
      icu_stays i
    ON 
      p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
    JOIN 
      procedures pr
    ON 
      i.subject_id = pr.subject_id AND i.hadm_id = pr.hadm_id AND i.stay_id = pr.stay_id
    WHERE 
      pr.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
    GROUP BY 
      p.subject_id, p.hadm_id
  ),
  
  -- Link with pneumonia and calculate LOS and mortality
  outcomes AS (
    SELECT 
      pc.subject_id,
      pc.hadm_id,
      pc.procedure_count,
      i.los,
      p.hospital_expire_flag
    FROM 
      procedure_counts pc
    JOIN 
      icu_stays i
    ON 
      pc.subject_id = i.subject_id AND pc.hadm_id = i.hadm_id
    JOIN 
      patients p
    ON 
      pc.subject_id = p.subject_id AND pc.hadm_id = p.hadm_id
    JOIN 
      pneumonia pn
    ON 
      pc.subject_id = pn.subject_id AND pc.hadm_id = pn.hadm_id
  )

-- Final calculation
SELECT 
  NTILE(5) OVER (ORDER BY procedure_count) AS quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(LOS / 24) AS avg_icu_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
FROM 
  outcomes
GROUP BY 
  quintile
ORDER BY 
  quintile;