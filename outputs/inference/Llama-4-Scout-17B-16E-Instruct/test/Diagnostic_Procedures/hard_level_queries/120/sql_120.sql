WITH 
-- Patient and admission data
patient_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
),

-- ICU stay data
icu_stay_data AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- First ICU stay for each admission
first_icu_stay AS (
  SELECT 
    hadm_id,
    MIN(intime) AS first_icu_intime,
    MIN(stay_id) AS first_icu_stay_id
  FROM 
    icu_stay_data
  GROUP BY 
    hadm_id
),

-- Diagnostic and procedure events in the first 72 hours of ICU stay
events_72hrs AS (
  SELECT 
    fis.first_icu_stay_id,
    COUNT(CASE 
            WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category = 'Procedure') THEN 1 
          END) AS procedure_count_72hrs,
    COUNT(DISTINCT CASE 
                      WHEN ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE category IN ('Lab', 'Vitals')) THEN ce.charttime 
                    END) AS diagnostic_events_72hrs
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    icu_stay_data icu
  ON 
    ce.subject_id = icu.subject_id AND ce.hadm_id = icu.hadm_id AND ce.stay_id = icu.stay_id
  JOIN 
    first_icu_stay fis
  ON 
    icu.hadm_id = fis.hadm_id AND icu.stay_id = fis.first_icu_stay_id
  WHERE 
    ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY 
    fis.first_icu_stay_id
),

-- Upper GI bleed admissions for male patients aged 74-84
target_population AS (
  SELECT 
    pd.subject_id,
    pd.hadm_id,
    pd.anchor_age,
    pd.gender,
    pd.hospital_expire_flag,
    pd.dischtime,
    pd.deathtime,
    fis.first_icu_stay_id,
    DATEDIFF(pd.dischtime, pd.admittime) AS hospital_los_days
  FROM 
    patient_data pd
  JOIN 
    first_icu_stay fis
  ON 
    pd.hadm_id = fis.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    pd.hadm_id = di.hadm_id
  WHERE 
    pd.gender = 'M' 
    AND pd.anchor_age BETWEEN 74 AND 84
    AND di.icd_code LIKE 'K25%'  -- Adjusted for upper GI bleeding
),

-- Prepare data for quartile calculation
quartile_data AS (
  SELECT 
    tp.hadm_id,
    COALESCE(e.procedure_count_72hrs, 0) AS procedure_count_72hrs,
    tp.hospital_los_days,
    tp.hospital_expire_flag
  FROM 
    target_population tp
  LEFT JOIN 
    events_72hrs e
  ON 
    tp.first_icu_stay_id = e.first_icu_stay_id
)

-- Final calculation
SELECT 
  de_quartile,
  AVG(procedure_count_72hrs) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality
FROM (
  SELECT 
    hadm_id,
    procedure_count_72hrs,
    hospital_los_days,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY diagnostic_events_72hrs) AS de_quartile
  FROM 
    quartile_data
) AS subquery
GROUP BY 
  de_quartile
ORDER BY 
  de_quartile;