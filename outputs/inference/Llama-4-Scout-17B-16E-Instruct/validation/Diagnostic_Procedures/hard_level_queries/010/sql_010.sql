WITH 
-- Identify male patients aged 40-50
patients_40_50 AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
),

-- Identify ICU stays for these patients
icu_stays_40_50 AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_40_50 p ON i.subject_id = p.subject_id
),

-- Identify patients with hemorrhagic stroke
hemorrhagic_stroke AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
  WHERE i.long_title LIKE '%Hemorrhagic stroke%'
),

-- Identify ICU stays for patients with hemorrhagic stroke
hemorrhagic_stroke_icu AS (
  SELECT i.stay_id
  FROM icu_stays_40_50 i
  JOIN hemorrhagic_stroke hs ON i.hadm_id = hs.hadm_id
),

-- Calculate diagnostic procedures within the first 72 hours
procedures_72hrs AS (
  SELECT 
    i.stay_id,
    COUNT(DISTINCT p.itemid) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN icu_stays_40_50 i ON p.stay_id = i.stay_id
  WHERE p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id
),

-- Calculate ICU LOS and in-hospital mortality
icu_outcomes AS (
  SELECT 
    i.stay_id,
    i.outtime - i.intime AS icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS in_hospital_mortality
  FROM icu_stays_40_50 i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),

-- Combine data
combined_data AS (
  SELECT 
    CASE 
      WHEN hs.stay_id IS NOT NULL THEN 'Hemorrhagic Stroke'
      ELSE 'Other'
    END AS patient_group,
    p.num_procedures,
    o.icu_los,
    o.in_hospital_mortality
  FROM procedures_72hrs p
  JOIN icu_outcomes o ON p.stay_id = o.stay_id
  LEFT JOIN hemorrhagic_stroke_icu hs ON p.stay_id = hs.stay_id
)

-- Calculate percentiles and averages
SELECT 
  patient_group,
  APPROX_QUANTILES(num_procedures, 1000)[90] AS p90_procedures,
  AVG(icu_los) AS avg_icu_los,
  AVG(in_hospital_mortality) AS avg_in_hospital_mortality
FROM combined_data
GROUP BY patient_group;