WITH 
-- Target population: Female ICU patients aged 56-66 with ICH
target_population AS (
  SELECT 
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND d.icd_code LIKE '907.0%'  -- Intracranial hemorrhage
    )
),

-- Diagnostic intensity during the first 72 hours
diagnostic_intensity AS (
  SELECT 
    tp.stay_id,
    COUNT(DISTINCT CASE 
      WHEN ce.itemid IS NOT NULL THEN ce.itemid 
      WHEN pe.itemid IS NOT NULL THEN pe.itemid 
      WHEN le.labevent_id IS NOT NULL THEN le.itemid 
    END) AS num_diagnostics
  FROM 
    target_population tp
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON tp.stay_id = ce.stay_id 
         AND TIMESTAMP_SUB(ce.charttime, INTERVAL 3 DAY) <= tp.admittime
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
      ON tp.stay_id = pe.stay_id 
         AND TIMESTAMP_SUB(pe.starttime, INTERVAL 3 DAY) <= tp.admittime
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON tp.hadm_id = le.hadm_id 
         AND TIMESTAMP_SUB(le.charttime, INTERVAL 3 DAY) <= tp.admittime
  GROUP BY 
    tp.stay_id
),

-- ICU length of stay and in-hospital mortality for target population
target_outcomes AS (
  SELECT 
    tp.stay_id,
    ic.los AS icu_los,
    tp.hospital_expire_flag
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON tp.stay_id = ic.stay_id
),

-- ICU length of stay and in-hospital mortality for overall ICU population
icu_outcomes AS (
  SELECT 
    ic.stay_id,
    ic.los AS icu_los,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON ic.hadm_id = a.hadm_id
)

-- Final calculations
SELECT 
  APPROX_QUANTILES(di.num_diagnostics, 100)[OFFSET(95)] AS percentile_95_diagnostic_intensity,
  AVG(to.icu_los) AS avg_icu_los_target,
  AVG(icu.icu_los) AS avg_icu_los_all,
  SUM(to.hospital_expire_flag) / COUNT(to.hospital_expire_flag) AS mortality_rate_target,
  SUM(icu.hospital_expire_flag) / COUNT(icu.hospital_expire_flag) AS mortality_rate_all
FROM 
  diagnostic_intensity di
  CROSS JOIN target_outcomes to_target  -- Renamed alias
  CROSS JOIN icu_outcomes icu;