WITH cohort_icu_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    adm.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'F'
    -- Age 52-62 at ICU admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 52 AND 62
    -- Filter for RRT during ICU stay
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.stay_id = ie.stay_id
        AND pe.itemid IN (225802, 225803, 225804, 225809, 225810, 225811, 225812, 225813) -- RRT procedure codes
    )
),

vital_sign_scores AS (
  SELECT 
    cis.stay_id,
    -- PLACEHOLDER: Replace with actual instability score calculation.
    -- Example: Average heart rate (items 220045, 211) in first 72 hours.
    AVG(ce.valuenum) AS instability_score
  FROM cohort_icu_stays cis
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cis.stay_id = ce.stay_id
    AND ce.charttime BETWEEN cis.intime AND DATETIME_ADD(cis.intime, INTERVAL 72 HOUR)
  WHERE ce.itemid IN (220045, 211) -- Heart rate items
  GROUP BY cis.stay_id
),

cohort_scores AS (
  SELECT 
    cis.*,
    vs.instability_score
  FROM cohort_icu_stays cis
  INNER JOIN vital_sign_scores vs
    ON cis.stay_id = vs.stay_id
),

percentile_calc AS (
  SELECT 
    -- Calculate percentile for score=65
    (SUM(CASE WHEN instability_score <= 65 THEN 1 ELSE 0 END) / COUNT(*)) * 100 AS percentile_65
  FROM cohort_scores
),

top_decile_data AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM cohort_scores
),

top_decile_agg AS (
  SELECT 
    AVG(los) AS mean_los_top_decile,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_top_decile
  FROM top_decile_data
  WHERE decile = 1 -- Top 10% of scores
)

SELECT 
  percentile_65,
  mean_los_top_decile,
  mortality_rate_top_decile
FROM percentile_calc, top_decile_agg;