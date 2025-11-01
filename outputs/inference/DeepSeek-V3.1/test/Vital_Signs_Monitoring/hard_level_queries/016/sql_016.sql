WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag AS mortality,
    CASE WHEN dx.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS transplant
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE (
      (icd_version = 10 AND icd_code LIKE 'T86%') OR
      (icd_version = 9 AND icd_code IN ('V42.0', 'V42.1', 'V42.7', 'V42.8', 'V42.9'))
    )
  ) dx 
    ON ie.hadm_id = dx.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 57 AND 67
),

instability_events AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS instability_score  -- Count each event (row) not distinct times
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE (
    (ce.itemid = 223761 AND ce.valuenum > 38.5) OR  -- Temperature Celsius
    (ce.itemid = 220277 AND ce.valuenum < 90) OR    -- SpO2
    (ce.itemid = 220210 AND ce.valuenum > 20)       -- Respiratory Rate
  )
  GROUP BY c.stay_id
)

SELECT 
  c.transplant,
  COUNT(*) AS n_stays,
  -- For instability score: median and percentiles
  APPROX_QUANTILES(COALESCE(ie.instability_score, 0), 100)[OFFSET(50)] AS median_instability,
  APPROX_QUANTILES(COALESCE(ie.instability_score, 0), 100)[OFFSET(25)] AS p25_instability,
  APPROX_QUANTILES(COALESCE(ie.instability_score, 0), 100)[OFFSET(75)] AS p75_instability,
  -- For ICU LOS
  APPROX_QUANTILES(c.los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(c.los, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(c.los, 100)[OFFSET(75)] AS p75_los,
  -- For mortality
  ROUND(SUM(c.mortality) / COUNT(*) * 100, 2) AS mortality_percent
FROM cohort c
LEFT JOIN instability_events ie
  ON c.stay_id = ie.stay_id
GROUP BY c.transplant
ORDER BY c.transplant;