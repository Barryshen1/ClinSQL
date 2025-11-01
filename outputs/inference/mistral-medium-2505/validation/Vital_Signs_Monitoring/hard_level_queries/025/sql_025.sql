WITH
-- Define post-cardiac arrest ICD codes
post_arrest_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I46.%' OR icd_code LIKE 'R09.2%'
),

-- Get male patients 55-65 with post-arrest diagnosis
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN post_arrest_icd pa ON d.icd_code = pa.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.admittime BETWEEN
      TIMESTAMP(DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR))
      AND TIMESTAMP(DATE_ADD(DATE(p.anchor_year, 12, 31), INTERVAL (65 - p.anchor_age) YEAR))
),

-- Get first ICU stay for each admission
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN cohort c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
  WHERE i.intime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  AND stay_seq = 1  -- Only first ICU stay per admission
),

-- Calculate vital sign instability score for first 24h of ICU stay
vital_signs AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    -- Example instability score calculation (simplified)
    -- In practice, this would be a more complex formula based on multiple vital signs
    SUM(
      CASE
        WHEN ce.itemid IN (220045, 220046) AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1 -- Heart rate
        WHEN ce.itemid IN (220050, 220051) AND ce.valuenum < 90 THEN 1 -- Systolic BP
        WHEN ce.itemid IN (220052, 220053) AND ce.valuenum < 60 THEN 1 -- Diastolic BP
        WHEN ce.itemid IN (220210, 220211) AND ce.valuenum < 90 THEN 1 -- SpO2
        ELSE 0
      END
    ) AS instability_score
  FROM first_icu_stay f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON f.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY f.subject_id, f.hadm_id, f.stay_id
),

-- Calculate percentiles
percentiles AS (
  SELECT
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM vital_signs
),

-- Get outcomes for most unstable decile
unstable_decile AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.instability_score,
    f.los AS icu_los,
    c.hospital_expire_flag
  FROM vital_signs v
  JOIN first_icu_stay f ON v.subject_id = f.subject_id AND v.hadm_id = f.hadm_id AND v.stay_id = f.stay_id
  JOIN cohort c ON v.subject_id = c.subject_id AND v.hadm_id = c.hadm_id
  WHERE v.instability_score >= (
    SELECT MAX(instability_score)
    FROM percentiles
    WHERE percentile <= 0.9
  )
)

-- Final results
SELECT
  -- Percentile for score of 70
  (SELECT percentile FROM percentiles WHERE instability_score = 70) AS percentile_for_70,

  -- Mean ICU LOS for most unstable decile
  AVG(icu_los) AS mean_icu_los_unstable_decile,

  -- Mortality rate for most unstable decile
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_unstable_decile

FROM unstable_decile;