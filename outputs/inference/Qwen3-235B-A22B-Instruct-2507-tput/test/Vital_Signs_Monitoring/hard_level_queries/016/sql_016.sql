WITH patient_cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.los AS icu_los,
    adm.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_admission,
    -- Determine transplant status for this admission
    MAX(CASE 
          WHEN dip.long_title LIKE '%transplant%' THEN 1 
          ELSE 0 
        END) AS is_transplant
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON ie.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 57 AND 67
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.los, adm.hospital_expire_flag, p.anchor_age, p.anchor_year
),
vitals AS (
  SELECT
    ce.stay_id,
    -- Flags for each instability criterion (any occurrence in first 72h)
    MAX(CASE WHEN di.label = 'Temperature' AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS has_fever,
    MAX(CASE WHEN di.label = 'O2 saturation pulse oximetry' AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_hypoxemia,
    MAX(CASE WHEN di.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS has_tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  INNER JOIN patient_cohort pc
    ON ce.stay_id = pc.stay_id
  WHERE ce.charttime >= pc.intime
    AND ce.charttime <= pc.intime + INTERVAL '72' HOUR
    AND di.label IN ('Temperature', 'O2 saturation pulse oximetry', 'Respiratory Rate')
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
instability_score AS (
  SELECT
    pc.stay_id,
    pc.is_transplant,
    COALESCE(v.has_fever, 0) AS has_fever,
    COALESCE(v.has_hypoxemia, 0) AS has_hypoxemia,
    COALESCE(v.has_tachypnea, 0) AS has_tachypnea,
    COALESCE(v.has_fever, 0) + COALESCE(v.has_hypoxemia, 0) + COALESCE(v.has_tachypnea, 0) AS composite_instability_score,
    pc.icu_los,
    pc.hospital_expire_flag
  FROM patient_cohort pc
  LEFT JOIN vitals v ON pc.stay_id = v.stay_id
)
-- Final aggregation: median, percentiles, and mortality by transplant status
SELECT
  is_transplant,
  -- Median and percentiles of composite instability score
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS instability_median,
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)] AS instability_p25,
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] AS instability_p75,
  -- Median and percentiles of ICU LOS
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS icu_los_median,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS icu_los_p25,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS icu_los_p75,
  -- Mortality rate
  AVG(hospital_expire_flag) AS mortality_rate
FROM instability_score
GROUP BY is_transplant
ORDER BY is_transplant;