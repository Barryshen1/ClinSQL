WITH patients_filtered AS (
  SELECT p.subject_id, p.gender, 
         p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 75 AND 85
),

vent_stays AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ventilation%'
    AND LOWER(di.label) LIKE '%invasive%'
    AND pe.statusdescription = 'Completed'
),

vitals_48h AS (
  SELECT ce.stay_id,
         ce.itemid,
         di.label,
         ce.valuenum,
         ce.charttime
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON ce.stay_id = i.stay_id
  WHERE ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND LOWER(di.label) IN (
        'heart rate',
        'arterial pressure systolic',
        'nibp systolic',
        'art pressure systolic'
    )
),

instability_events AS (
  SELECT stay_id,
         SUM(CASE WHEN LOWER(label) LIKE '%systolic%' AND valuenum < 90 THEN 1 ELSE 0 END) AS hypotension_count,
         SUM(CASE WHEN LOWER(label) = 'heart rate' AND valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count
  FROM vitals_48h
  GROUP BY stay_id
),

composite_score AS (
  SELECT ie.stay_id,
         (ie.hypotension_count + ie.tachycardia_count) AS instability_score,
         ie.hypotension_count,
         ie.tachycardia_count,
         i.los AS icu_los,
         a.hospital_expire_flag,
         i.intime,
         i.hadm_id
  FROM instability_events ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON ie.stay_id = i.stay_id
  INNER JOIN vent_stays v
    ON i.stay_id = v.stay_id
  INNER JOIN patients_filtered pf
    ON i.subject_id = pf.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON i.hadm_id = a.hadm_id
),

percentiles AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM composite_score
  LIMIT 1
),

score_with_quartile AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM composite_score
),

top_25_percent AS (
  SELECT *
  FROM score_with_quartile
  WHERE instability_quartile = 4
)

SELECT
  (SELECT p90_score FROM percentiles) AS p90_composite_instability_score,
  AVG(CASE WHEN hypotension_count > 0 THEN 1.0 ELSE 0.0 END) AS pct_hypotension_in_top_25,
  AVG(CASE WHEN tachycardia_count > 0 THEN 1.0 ELSE 0.0 END) AS pct_tachycardia_in_top_25,
  AVG(icu_los) AS avg_icu_los_in_top_25,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_in_top_25
FROM top_25_percent;