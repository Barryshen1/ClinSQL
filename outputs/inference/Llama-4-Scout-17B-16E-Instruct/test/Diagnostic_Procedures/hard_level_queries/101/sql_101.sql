WITH 
  -- Identify COPD exacerbation ICD codes
  copd_exacerbation AS (
    SELECT 
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE 
      long_title LIKE '%COPD exacerbation%'
  ),

  -- Select relevant patient and admission data
  patients_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),

  -- Select ICU stay data
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

  -- Identify procedures within the first 72 hours of ICU stay
  icu_procedures AS (
    SELECT 
      ip.subject_id,
      ip.hadm_id,
      ip.stay_id,
      COUNT(DISTINCT ip.itemid) AS distinct_procedures
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents` ip
    JOIN 
      icu_stays ic
    ON 
      ip.hadm_id = ic.hadm_id AND ip.stay_id = ic.stay_id
    WHERE 
      ip.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY 
      ip.subject_id, ip.hadm_id, ip.stay_id
  ),

  -- Filter for male patients with COPD exacerbation aged 88-98
  target_population AS (
    SELECT 
      pa.subject_id,
      pa.hadm_id,
      pa.anchor_age,
      pa.admittime,
      pa.dischtime,
      pa.deathtime,
      pa.hospital_expire_flag,
      pa.gender,
      ic.stay_id,
      ic.intime AS icu_intime,
      ic.outtime AS icu_outtime,
      ic.los AS icu_los
    FROM 
      patients_admissions pa
    JOIN 
      icu_stays ic
    ON 
      pa.hadm_id = ic.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON 
      pa.hadm_id = di.hadm_id
    WHERE 
      pa.anchor_age BETWEEN 88 AND 98
      AND pa.gender = 'M'
      AND di.icd_code IN (SELECT icd_code FROM copd_exacerbation)
  )

-- Calculate 75th percentile of distinct procedures, mean ICU LOS, and in-hospital mortality
SELECT 
  APPROX_QUANTILES(distinct_procedures, 0.75) AS percentile_75th_procedures,
  AVG(icu_los) AS mean_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id) AS in_hospital_mortality_rate
FROM (
  SELECT 
    ta.hadm_id,
    ta.hospital_expire_flag,
    ip.distinct_procedures,
    ta.icu_los
  FROM 
    target_population ta
  JOIN 
    icu_procedures ip
  ON 
    ta.subject_id = ip.subject_id AND ta.hadm_id = ip.hadm_id AND ta.stay_id = ip.stay_id
);