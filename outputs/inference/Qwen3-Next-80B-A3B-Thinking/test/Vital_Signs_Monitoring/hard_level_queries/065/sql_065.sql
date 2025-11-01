WITH cohort AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 70 AND 80
),
rrt_status AS (
  SELECT
    i.stay_id,
    MAX(CASE WHEN pe.itemid IN (227536, 227537, 227538) THEN 1 ELSE 0 END) AS has_rrt
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime BETWEEN i.intime AND i.outtime
  GROUP BY i.stay_id
),
composite_score AS (
  SELECT
    c.stay_id,
    SUM(CASE WHEN ce.itemid IN (456, 220050) AND ce.valuenum IS NOT NULL AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    (SUM(CASE WHEN ce.itemid IN (456, 220050) AND ce.valuenum IS NOT NULL AND ce.valuenum < 65 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 100 THEN 1 ELSE 0 END)) AS composite_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
combined AS (
  SELECT
    c.stay_id,
    c.hospital_expire_flag,
    c.intime,
    c.outtime,
    r.has_rrt,
    cs.hypotension_count,
    cs.tachycardia_count,
    cs.composite_score
  FROM cohort c
  JOIN rrt_status r ON c.stay_id = r.stay_id
  JOIN composite_score cs ON c.stay_id = cs.stay_id
),
p90_val AS (
  SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90
  FROM combined
  WHERE has_rrt = 1
)
SELECT
  '90th Percentile' AS `group`,
  p90 AS composite_score,
  NULL AS avg_hypotension,
  NULL AS avg_tachycardia,
  NULL AS avg_los,
  NULL AS mortality_rate
FROM p90_val
UNION ALL
SELECT
  'RRT Top Decile' AS `group`,
  NULL,
  AVG(hypotension_count),
  AVG(tachycardia_count),
  AVG(DATE_DIFF(outtime, intime, 'DAY')),
  AVG(CAST(hospital_expire_flag AS FLOAT64))
FROM combined
WHERE has_rrt = 1 AND composite_score >= (SELECT p90 FROM p90_val)
UNION ALL
SELECT
  'Non-RRT' AS `group`,
  NULL,
  AVG(hypotension_count),
  AVG(tachycardia_count),
  AVG(DATE_DIFF(outtime, intime, 'DAY')),
  AVG(CAST(hospital_expire_flag AS FLOAT64))
FROM combined
WHERE has_rrt = 0;