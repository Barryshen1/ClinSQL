WITH 
  -- Filter patients: female, aged 65-75, with pulmonary embolism
  patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 65 AND 75
      AND a.hadm_id IN (
        SELECT 
          hadm_id
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE 
          icd_code LIKE '415.1%'  -- Pulmonary embolism ICD-9 code
          OR icd_code LIKE 'I26.%'  -- Pulmonary embolism ICD-10 code
      )
  ),

  -- ICU stay information
  icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Procedure events within 72 hours of ICU stay
  procedure_events AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      COUNT(pe.itemid) AS procedure_count,
      p.hospital_expire_flag,
      i.los
    FROM 
      patients p
    JOIN 
      icu_stays i
    ON 
      p.hadm_id = i.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON 
      i.stay_id = pe.stay_id
      AND pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
    GROUP BY 
      p.subject_id, p.hadm_id, p.hospital_expire_flag, i.los
  ),

  -- Calculate quartiles
  procedure_events_with_quartile AS (
    SELECT 
      subject_id,
      hadm_id,
      procedure_count,
      hospital_expire_flag,
      los,
      NTILE(4) OVER (ORDER BY procedure_count) AS quartile
    FROM 
      procedure_events
  )

-- Calculate and report statistics per quartile
SELECT 
  quartile,
  COUNT(*) AS N,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los / 24) AS mean_icu_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS hospital_mortality_pct
FROM 
  procedure_events_with_quartile
GROUP BY 
  quartile
ORDER BY 
  quartile;