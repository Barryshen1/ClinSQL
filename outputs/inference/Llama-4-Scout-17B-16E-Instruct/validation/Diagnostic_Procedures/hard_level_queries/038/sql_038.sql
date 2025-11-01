WITH 
-- Identify target population: male patients aged 60-70 with intracranial hemorrhage
target_population AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 60 AND 70 
    AND d.icd_code IN ('907.0', '851.0', '851.1', '851.2', '851.3', '851.4', '851.5', '851.6', '851.7', '851.8', '851.9') 
    AND ic.first_careunit = ic.last_careunit  -- First ICU stay
),

-- Calculate procedure burden in the first 72h
procedure_burden AS (
  SELECT 
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON pe.stay_id = ic.stay_id
  WHERE 
    pe.stay_id IN (SELECT stay_id FROM target_population)
    AND pe.endtime <= TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
  GROUP BY 
    pe.stay_id
),

-- Calculate ICU LOS and hospital mortality for target population
icu_outcomes AS (
  SELECT 
    tp.stay_id,
    TIMESTAMP_DIFF(ic.outtime, ic.intime, DAY) AS icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS hospital_mortality
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON tp.stay_id = ic.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON tp.hadm_id = a.hadm_id
),

-- General ICU population for comparison
general_icu_population AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(ic.outtime, ic.intime, DAY)) AS mean_icu_los_general,
    AVG(CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END) AS hospital_mortality_general
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
)

-- Final calculations
SELECT 
  APPROX_QUANTILES(procedure_count, 0.75)[OFFSET(1)] AS percentile_75th_procedure_burden,
  AVG(icu_los) AS mean_icu_los_target,
  AVG(hospital_mortality) AS hospital_mortality_target,
  g.mean_icu_los_general,
  g.hospital_mortality_general
FROM 
  procedure_burden
  CROSS JOIN (
    SELECT 
      AVG(icu_los) AS mean_icu_los,
      AVG(hospital_mortality) AS hospital_mortality
    FROM 
      icu_outcomes
  ) AS icu_outcomes
  CROSS JOIN general_icu_population g;