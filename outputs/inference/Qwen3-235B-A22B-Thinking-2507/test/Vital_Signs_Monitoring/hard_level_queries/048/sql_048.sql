WITH patient_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 75 AND 85
),

ventilated_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.stay_id
  FROM patient_cohort p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON p.subject_id = c.subject_id AND p.stay_id = c.stay_id
  WHERE c.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 48 HOUR)
    AND c.itemid IN (
      223830, -- Tidal Volume (set)
      223848, -- Respiratory Rate (set)
      223849, -- Respiratory Rate (spontaneous)
      223988  -- Ventilator Mode
    )
),

instability_scores AS (
  SELECT
    p.subject_id,
    p.stay_id,
    COUNT(CASE 
            WHEN c.itemid IN (220050, 220179, 220180, 220181) -- Systolic BP itemids
                 AND c.valuenum < 90 THEN 1
            WHEN c.itemid IN (220052) -- MAP itemid
                 AND c.valuenum < 65 THEN 1
            WHEN c.itemid IN (220045) -- Heart rate itemid
                 AND c.valuenum > 100 THEN 1
            ELSE NULL
          END) AS instability_score
  FROM patient_cohort p
  INNER JOIN ventilated_patients v ON p.subject_id = v.subject_id AND p.stay_id = v.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON p.subject_id = c.subject_id AND p.stay_id = c.stay_id
  WHERE c.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 48 HOUR)
    AND c.itemid IN (
      220050, 220179, 220180, 220181, -- Systolic BP
      220052, -- MAP
      220045  -- Heart rate
    )
  GROUP BY p.subject_id, p.stay_id
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS percentile_90,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS percentile_75
  FROM instability_scores
),

top_instability AS (
  SELECT
    iscore.*
  FROM instability_scores iscore
  CROSS JOIN percentiles p
  WHERE iscore.instability_score >= p.percentile_75
),

outcomes AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(CASE WHEN has_hypotension THEN 1 ELSE 0 END) AS hypotension_rate,
    AVG(CASE WHEN has_tachycardia THEN 1 ELSE 0 END) AS tachycardia_rate,
    AVG(los_days) AS avg_los,
    AVG(mortality) AS mortality_rate
  FROM (
    SELECT
      t.subject_id,
      t.stay_id,
      MAX(CASE 
            WHEN c.itemid IN (220050, 220179, 220180, 220181) AND c.valuenum < 90 THEN 1
            WHEN c.itemid IN (220052) AND c.valuenum < 65 THEN 1
            ELSE 0
          END) = 1 AS has_hypotension,
      MAX(CASE 
            WHEN c.itemid IN (220045) AND c.valuenum > 100 THEN 1
            ELSE 0
          END) = 1 AS has_tachycardia,
      DATETIME_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS los_days,
      a.hospital_expire_flag AS mortality
    FROM top_instability t
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON t.stay_id = i.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
      ON t.subject_id = c.subject_id AND t.stay_id = c.stay_id
      AND c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
      AND c.itemid IN (220050, 220179, 220180, 220181, 220052, 220045)
    GROUP BY t.subject_id, t.stay_id, i.outtime, i.intime, a.hospital_expire_flag
  ) sub
)

SELECT
  (SELECT percentile_90 FROM percentiles) AS percentile_90,
  hypotension_rate,
  tachycardia_rate,
  avg_los,
  mortality_rate
FROM outcomes;