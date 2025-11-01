WITH cohort AS (
  SELECT 
    icustays.stay_id,
    icustays.hadm_id,
    icustays.subject_id,
    icustays.intime,
    icustays.outtime,
    patients.anchor_age,
    patients.anchor_year,
    patients.gender,
    patients.anchor_age + EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'F'
    AND (patients.anchor_age + EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
      WHERE chartevents.stay_id = icustays.stay_id
        AND chartevents.itemid = 223848
        AND chartevents.value = 'Intubated'
        AND chartevents.charttime BETWEEN icustays.intime AND icustays.outtime
    )
),

composite_scores AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.intime,
    c.outtime,
    c.hadm_id,
    COUNTIF(
      ce.itemid = 220050 
      AND ce.valuenum < 90 
      AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    ) AS sbp_count,
    COUNTIF(
      ce.itemid = 220045 
      AND ce.valuenum > 100 
      AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    ) AS hr_count,
    (COUNTIF(ce.itemid = 220050 AND ce.valuenum < 90 AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)) +
     COUNTIF(ce.itemid = 220045 AND ce.valuenum > 100 AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR))) AS composite_score,
    MAX(CASE WHEN ce.itemid = 220050 AND ce.valuenum < 90 AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS has_hypotension,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS has_tachycardia,
    DATETIME_DIFF(c.outtime, c.intime, DAY) AS los_days,
    hosp.hospital_expire_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` hosp
    ON c.hadm_id = hosp.hadm_id
  GROUP BY c.stay_id, c.subject_id, c.intime, c.outtime, c.hadm_id, hosp.hospital_expire_flag
),

p90 AS (
  SELECT 
    PERCENTILE_CONT(composite_score, 0.9) OVER() AS p90_value
  FROM composite_scores
  LIMIT 1
),

ranked AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY composite_score DESC) AS quartile
  FROM composite_scores
)

SELECT 
  (SELECT p90_value FROM p90) AS p90_composite_score,
  AVG(has_hypotension) * 100 AS hypotension_rate,
  AVG(has_tachycardia) * 100 AS tachycardia_rate,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate
FROM ranked
WHERE quartile = 1;