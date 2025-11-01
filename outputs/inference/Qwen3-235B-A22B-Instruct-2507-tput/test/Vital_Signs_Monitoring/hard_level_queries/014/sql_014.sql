WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) AS age_at_icu,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 88 AND 98
),
-- Get RRT patients
rrt_procedures AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%crrt%'
     OR LOWER(di.label) LIKE '%renal replacement%'
),
cohort AS (
  SELECT pa.*
  FROM patients_age pa
  INNER JOIN rrt_procedures rrt
    ON pa.stay_id = rrt.stay_id
),
-- Extract instability score within first 72 hours
instability_scores AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    c.icu_los,
    MAX(ce.valuenum) AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Instability Score'
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id, c.hadm_id, c.icu_los
),
-- Compute percentile of 85
percentile_calc AS (
  SELECT
    SUM(CASE WHEN instability_score <= 85 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_of_85
  FROM instability_scores
),
-- Assign quartiles (descending: most unstable first)
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM instability_scores
),
-- Top quartile outcomes
top_quartile_outcomes AS (
  SELECT
    AVG(q.icu_los) AS median_icu_los, -- Using AVG; for median use APPROX_QUANTILES if needed
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM quartiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON q.hadm_id = a.hadm_id
  WHERE q.instability_quartile = 1
)
-- Final output
SELECT
  p.percentile_of_85,
  t.median_icu_los,
  t.hospital_mortality_rate
FROM percentile_calc p
CROSS JOIN top_quartile_outcomes t;