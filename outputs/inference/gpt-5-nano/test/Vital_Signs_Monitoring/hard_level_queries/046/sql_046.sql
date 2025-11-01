WITH cohort AS (
  -- Ischemic stroke ischemic diagnosis in a male patient aged 84-94
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON i.subject_id = di.subject_id AND i.hadm_id = di.hadm_id
  WHERE CAST(p.anchor_age AS INT64) BETWEEN 84 AND 94
    AND p.gender = 'M'
    AND di.icd_version = 10
    AND di.icd_code LIKE 'I63%'
),
vitals AS (
  -- Vital signs within the first 72 hours of ICU intime
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    CASE
      WHEN LOWER(d.label) LIKE '%heart rate%' THEN 'HR'
      WHEN LOWER(d.label) LIKE '%systolic blood pressure%' OR LOWER(d.label) LIKE '%blood pressure systolic%' THEN 'SBP'
      WHEN LOWER(d.label) LIKE '%respiratory rate%' THEN 'RR'
      WHEN LOWER(d.label) LIKE '%spo2%' OR LOWER(d.label) LIKE '%oxygen saturation%' THEN 'SpO2'
      WHEN LOWER(d.label) LIKE '%temperature%' THEN 'Temp'
    END AS vital,
    ce.valuenum AS valnum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON ce.itemid = d.itemid
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
),
flags AS (
  -- Abnormality flags for each stay
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.intime,
    a.hospital_expire_flag AS death,
    MAX(CASE WHEN v.vital = 'HR'  AND (v.valnum < 60 OR v.valnum > 100) THEN 1 ELSE 0 END) AS hr_abn,
    MAX(CASE WHEN v.vital = 'SBP' AND (v.valnum < 90 OR v.valnum > 180) THEN 1 ELSE 0 END) AS sbp_abn,
    MAX(CASE WHEN v.vital = 'RR'  AND (v.valnum < 8 OR v.valnum > 40) THEN 1 ELSE 0 END) AS rr_abn,
    MAX(CASE WHEN v.vital = 'SpO2' AND (v.valnum < 92) THEN 1 ELSE 0 END) AS spo2_abn,
    MAX(CASE WHEN v.vital = 'Temp' AND (v.valnum < 36 OR v.valnum > 38.5) THEN 1 ELSE 0 END) AS temp_abn
  FROM vitals v
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON v.hadm_id = a.hadm_id
  GROUP BY v.subject_id, v.hadm_id, v.stay_id, v.intime, a.hospital_expire_flag
),
scores AS (
  -- Instability score per ICU stay (hours to days conversion later)
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    i.los/24 AS icu_los_days,        -- ICU LOS in days (adjust if needed based on los unit)
    f.death,
    30*CAST(f.hr_abn AS INT64)   + 25*CAST(f.sbp_abn AS INT64) +
    20*CAST(f.rr_abn AS INT64)   + 15*CAST(f.spo2_abn AS INT64) +
    10*CAST(f.temp_abn AS INT64) AS instability_score
  FROM flags f
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON f.subject_id = i.subject_id
   AND f.hadm_id = i.hadm_id
   AND f.stay_id = i.stay_id
),
-- Determine 75th percentile threshold for top quartile
thr AS (
  SELECT quantiles[OFFSET(3)] AS p75
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 4) AS quantiles
    FROM scores
  )
),
top AS (
  SELECT s.*
  FROM scores s
  CROSS JOIN thr
  WHERE s.instability_score >= thr.p75
),
top_los_median AS (
  SELECT quantiles[OFFSET(1)] AS top_los_median_days
  FROM (
    SELECT APPROX_QUANTILES(icu_los_days, 2) AS quantiles
    FROM top
  )
),
top_mortality AS (
  SELECT 100.0 * SUM(death) / COUNT(*) AS top_mortality_percent
  FROM top
),
percentile_80 AS (
  SELECT 100.0 * COUNTIF(instability_score <= 80) / COUNT(*) AS percentile_80
  FROM scores
)
SELECT
  percentile_80.percentile_80,
  top_los_median.top_los_median_days,
  top_mortality.top_mortality_percent
FROM percentile_80
CROSS JOIN top_los_median
CROSS JOIN top_mortality;