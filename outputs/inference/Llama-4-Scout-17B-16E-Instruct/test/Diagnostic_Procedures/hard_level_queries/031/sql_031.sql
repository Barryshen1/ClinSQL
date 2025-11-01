WITH 
  -- Filter patients and calculate procedure burden
  patient_info AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id,
      a.admittime,
      a.hospital_expire_flag,
      a.dischtime,
      a.admission_location
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' AND p.anchor_age BETWEEN 66 AND 76
      AND a.admission_location IN ('Hospice', 'Home Health', 'Skilled Nursing')
  ),
  
  icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  procedure_burden AS (
    SELECT 
      icu_stay.stay_id,
      COUNT(pe.itemid) AS procedure_count
    FROM 
      icu_stays icu_stay
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON 
      icu_stay.stay_id = pe.stay_id
    WHERE 
      pe.starttime BETWEEN icu_stay.intime AND TIMESTAMP_ADD(icu_stay.intime, INTERVAL 48 HOUR)
    GROUP BY 
      icu_stay.stay_id
  ),
  
  -- Calculate hospital LOS and 30-day readmission
  hospital_outcomes AS (
    SELECT 
      pi.hadm_id,
      pi.hospital_expire_flag,
      TIMESTAMP_DIFF(pi.dischtime, pi.admittime, DAY) AS hospital_los,
      CASE 
        WHEN EXISTS (
          SELECT 
            1 
          FROM 
            `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE 
            a2.subject_id = pi.subject_id 
            AND a2.admittime BETWEEN TIMESTAMP_ADD(pi.dischtime, INTERVAL 1 DAY) 
            AND TIMESTAMP_ADD(pi.dischtime, INTERVAL 30 DAY)
        ) THEN 1 
        ELSE 0 
      END AS readmitted
    FROM 
      patient_info pi
  ),
  
  -- Combine procedure burden with hospital outcomes
  combined_info AS (
    SELECT 
      pb.stay_id,
      pb.procedure_count,
      ho.hadm_id,
      ho.hospital_expire_flag,
      ho.hospital_los,
      ho.readmitted
    FROM 
      procedure_burden pb
    JOIN 
      icu_stays icu_stay
    ON 
      pb.stay_id = icu_stay.stay_id
    JOIN 
      hospital_outcomes ho
    ON 
      icu_stay.hadm_id = ho.hadm_id
  )

-- Stratify into quintiles and calculate statistics
SELECT 
  quintile,
  COUNT(DISTINCT stay_id) AS num_icu_stays,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS hospital_mortality_pct,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(readmitted) * 100 AS thirty_day_readmission_pct
FROM (
  SELECT 
    stay_id,
    procedure_count,
    hadm_id,
    hospital_expire_flag,
    hospital_los,
    readmitted,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM 
    combined_info
)
GROUP BY 
  quintile
ORDER BY 
  quintile;