WITH 
-- Identify patients with UGIB
ugib_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code LIKE 'K92.0%'  -- Upper GI bleeding
),

-- Identify ICU stays for UGIB patients
icustays_ugib AS (
  SELECT 
    i.stay_id, 
    i.hadm_id, 
    i.subject_id, 
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    ugib_patients u 
      ON i.hadm_id = u.hadm_id
),

-- Count procedures within the first 24 hours of ICU admission
procedures_24hrs AS (
  SELECT 
    stay_id, 
    COUNT(*) AS procedure_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE 
    starttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
  GROUP BY 
    stay_id
),

-- Join ICU stays with procedure counts
icustays_with_procedures AS (
  SELECT 
    i.stay_id, 
    i.hadm_id, 
    i.subject_id, 
    COALESCE(p.procedure_count, 0) AS procedure_count,
    i.intime
  FROM 
    icustays_ugib i
  LEFT JOIN 
    procedures_24hrs p 
      ON i.stay_id = p.stay_id
),

-- Calculate quintiles of procedure counts
quintiles AS (
  SELECT 
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM 
    icustays_with_procedures
),

-- Prepare data for final aggregation
data_for_aggregation AS (
  SELECT 
    q.quintile,
    q.procedure_count AS procedures,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    IF(a.hospital_expire_flag = 1, 1.0, 0.0) AS in_hospital_mortality
  FROM 
    quintiles q
  JOIN 
    icustays_with_procedures iwp 
      ON q.procedure_count = iwp.procedure_count
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON iwp.hadm_id = a.hadm_id
)

-- Calculate average procedures, hospital LOS, and in-hospital mortality per quintile
SELECT 
  quintile,
  AVG(procedures) AS avg_procedures,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_hospital_los,
  AVG(in_hospital_mortality) * 100 AS in_hospital_mortality_pct
FROM 
  data_for_aggregation
GROUP BY 
  quintile
ORDER BY 
  quintile;