WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 37 AND 47
),
ventilated_stays AS (
  SELECT DISTINCT
    c.stay_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime BETWEEN c.intime AND c.outtime
  WHERE 
    pe.itemid = 227194  -- Non-Invasive Ventilation (CPAP/BiPAP)
),
max_dias_bp_per_stay AS (
  SELECT 
    vs.stay_id,
    MAX(ce.valuenum) AS max_dias_bp
  FROM ventilated_stays vs
  INNER JOIN cohort c 
    ON vs.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON vs.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND c.outtime
  WHERE 
    ce.itemid IN (
      220180,  -- Non-Invasive BP Diastolic
      225310,  -- ART BP Diastolic
      8555,    -- Manual BP Diastolic (Left)
      8441,    -- Manual BP Diastolic (Right)
      224643,  -- Manual BP Diastolic Left (2)
      227243   -- Manual BP Diastolic Right (2)
    )
    AND ce.valuenum > 0  -- Valid numeric values
  GROUP BY vs.stay_id
)
SELECT 
  APPROX_QUANTILES(max_dias_bp, 100)[OFFSET(25)] AS percentile_25
FROM max_dias_bp_per_stay;