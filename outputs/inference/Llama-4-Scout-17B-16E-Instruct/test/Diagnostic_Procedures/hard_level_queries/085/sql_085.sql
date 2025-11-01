WITH 
  -- Patient demographics and admission information
  patient_info AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
  ),

  -- First ICU stay information
  icu_stay_info AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      first_careunit,
      intime,
      outtime,
      los
    FROM (
      SELECT 
        subject_id,
        hadm_id,
        stay_id,
        first_careunit,
        intime,
        outtime,
        los,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
      FROM 
        `physionet-data.mimiciv_3_1_icu.icustays`
    ) t
    WHERE 
      rn = 1
  ),

  -- Procedures in the first 48 hours of ICU stay
  procedures_48hrs AS (
    SELECT 
      pe.subject_id,
      pe.hadm_id,
      pe.stay_id,
      COUNT(DISTINCT pe.itemid) AS distinct_procedures
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN 
      icu_stay_info isi
    ON 
      pe.subject_id = isi.subject_id AND pe.hadm_id = isi.hadm_id AND pe.stay_id = isi.stay_id
    WHERE 
      pe.starttime BETWEEN isi.intime AND TIMESTAMP_ADD(isi.intime, INTERVAL 48 HOUR)
    GROUP BY 
      pe.subject_id, pe.hadm_id, pe.stay_id
  ),

  -- Filter and calculate mortality
  filtered_patients AS (
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      pi.gender,
      pi.anchor_age,
      isi.stay_id,
      isi.los,
      pi.hospital_expire_flag,
      pr.distinct_procedures
    FROM 
      patient_info pi
    JOIN 
      icu_stay_info isi
    ON 
      pi.subject_id = isi.subject_id AND pi.hadm_id = isi.hadm_id
    JOIN 
      procedures_48hrs pr
    ON 
      pi.subject_id = pr.subject_id AND pi.hadm_id = pr.hadm_id AND isi.stay_id = pr.stay_id
    WHERE 
      pi.gender = 'F'
      AND pi.anchor_age BETWEEN 87 AND 97
      AND pi.hospital_expire_flag IS NOT NULL
  ),

  -- Calculate quintiles
  patient_quintiles AS (
    SELECT 
      *,
      NTILE(5) OVER (ORDER BY distinct_procedures) AS quintile
    FROM 
      filtered_patients
  )

-- Calculate statistics
SELECT 
  quintile,
  AVG(distinct_procedures) AS mean_procedure_count,
  AVG(los / 24) AS mean_icu_los_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate
FROM 
  patient_quintiles
GROUP BY 
  quintile
ORDER BY 
  quintile;