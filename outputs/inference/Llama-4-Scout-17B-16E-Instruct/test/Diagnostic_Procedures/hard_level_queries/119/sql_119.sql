WITH 
-- Identify AMI patients and relevant information
ami_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 42 AND 52
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9')
        AND icd_version = 'ICD-9'
    )
),

-- ICU stay information
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

-- Procedures within the first 72 hours of ICU stay
procedures_icu AS (
  SELECT 
    i.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM 
    icu_stays i
  JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON 
    i.stay_id = pe.stay_id
  WHERE 
    pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY 
    i.stay_id
),

-- Hospital LOS and mortality
hospital_outcomes AS (
  SELECT 
    a.hadm_id,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

-- Main query
SELECT 
  APPROX_QUANTILES(p.distinct_procedures, 0.9)[OFFSET(0)] AS diagnostic_intensity_90th,
  AVG(TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY)) AS mean_hospital_los,
  AVG(h.hospital_expire_flag) AS in_hospital_mortality_rate
FROM 
  ami_patients ap
  JOIN icu_stays ic ON ap.hadm_id = ic.hadm_id
  JOIN procedures_icu p ON ic.stay_id = p.stay_id
  JOIN hospital_outcomes h ON ap.hadm_id = h.hadm_id;