WITH 
  -- Identify target patients
  target_patients AS (
    SELECT 
      p.subject_id, 
      p.gender, 
      p.anchor_age, 
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 37 AND 47
  ),

  -- Identify first ICU stay
  first_icu_stay AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      intime,
      outtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Procedures within first 48 hours
  procedures_48hrs AS (
    SELECT 
      fis.subject_id, 
      fis.hadm_id, 
      fis.stay_id,
      COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM 
      first_icu_stay fis
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON 
      fis.stay_id = pe.stay_id
    WHERE 
      pe.starttime BETWEEN fis.intime AND TIMESTAMP_ADD(fis.intime, INTERVAL 48 HOUR)
      AND fis.rn = 1
    GROUP BY 
      fis.subject_id, 
      fis.hadm_id, 
      fis.stay_id
  ),

  -- Quintile stratification
  quintiles AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      distinct_procedure_count,
      NTILE(5) OVER (ORDER BY distinct_procedure_count) AS quintile
    FROM 
      procedures_48hrs
  ),

  -- ICU LOS and hospital mortality
  icu_outcomes AS (
    SELECT 
      fis.subject_id, 
      fis.hadm_id, 
      fis.stay_id,
      TIMESTAMP_DIFF(fis.outtime, fis.intime, DAY) AS icu_los_days,
      CASE 
        WHEN a.hospital_expire_flag = 1 THEN 1 
        ELSE 0 
      END AS hospital_mortality
    FROM 
      first_icu_stay fis
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      fis.hadm_id = a.hadm_id
    WHERE 
      fis.rn = 1
  )

-- Final aggregation
SELECT 
  q.quintile,
  AVG(q.distinct_procedure_count) AS mean_procedure_count,
  AVG(io.icu_los_days) AS mean_icu_los_days,
  AVG(io.hospital_mortality) AS hospital_mortality_rate
FROM 
  quintiles q
JOIN 
  icu_outcomes io
ON 
  q.subject_id = io.subject_id
  AND q.hadm_id = io.hadm_id
  AND q.stay_id = io.stay_id
GROUP BY 
  q.quintile
ORDER BY 
  q.quintile;