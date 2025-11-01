WITH cohort AS (
  -- Base cohort: male patients aged 42-52 with AMI primary diagnosis and ICU stay
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND d.seq_num = 1
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '410%') OR
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I21%')
    )
),

first_stays AS (
  -- Select first ICU stay per admission
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    admittime,
    dischtime,
    hospital_expire_flag,
    anchor_age,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY stay_id) AS rn
  FROM cohort
),

diagnostic_intensity AS (
  -- Distinct procedures in first 72 ICU hours per first stay
  SELECT 
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_distinct_procedures
  FROM 
    first_stays fs
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fs.subject_id = pe.subject_id 
    AND fs.hadm_id = pe.hadm_id 
    AND fs.stay_id = pe.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime <= TIMESTAMP_ADD(fs.intime, INTERVAL 72 HOUR)
    AND pe.itemid IS NOT NULL  -- Valid procedure items
  WHERE 
    fs.rn = 1
  GROUP BY 
    fs.subject_id, fs.hadm_id, fs.stay_id
),

los_mortality AS (
  -- LOS and mortality per qualifying admission (linked to first ICU stay)
  SELECT 
    subject_id,
    hadm_id,
    anchor_age,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS hospital_los_days,
    hospital_expire_flag
  FROM 
    first_stays
  WHERE 
    rn = 1
)

-- Final aggregates
SELECT 
  PERCENTILE_CONT(0.9) OVER () AS p90_diagnostic_intensity,
  AVG(lm.hospital_los_days) AS mean_hospital_los_days,
  AVG(lm.hospital_expire_flag * 1.0) AS mean_inhospital_mortality_rate,
  AVG(lm.anchor_age) AS mean_age  -- For reference in age-matched comparison
FROM 
  los_mortality lm
LEFT JOIN 
  diagnostic_intensity di
  ON lm.subject_id = di.subject_id AND lm.hadm_id = di.hadm_id;