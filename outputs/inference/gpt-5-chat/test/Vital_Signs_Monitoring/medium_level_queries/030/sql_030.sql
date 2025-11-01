WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
temp_items AS (
  SELECT
    itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND (LOWER(unitname) LIKE '%c%' OR LOWER(unitname) LIKE '%cel%')
),
first24h_temps AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.valuenum AS temp_c
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM temp_items)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),
per_stay_mean_temp AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(temp_c) AS mean_temp_c
  FROM first24h_temps
  GROUP BY subject_id, hadm_id, stay_id
),
temp_classified AS (
  SELECT
    ps.*,
    CASE
      WHEN mean_temp_c < 36.0 THEN '<36.0'
      WHEN mean_temp_c >= 38.0 THEN '>=38.0'
      ELSE '36.0-37.9'
    END AS temp_group
  FROM per_stay_mean_temp ps
),
mi_flags AS (
  SELECT
    hadm_id,
    MAX( CASE
      WHEN (d.icd_version = 9 AND icd_code LIKE '410%')
        OR (d.icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
      THEN 1 ELSE 0 END ) AS mi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY hadm_id
),
joined AS (
  SELECT
    t.stay_id,
    t.mean_temp_c,
    t.temp_group,
    IFNULL(m.mi_flag, 0) AS mi_flag
  FROM temp_classified t
  LEFT JOIN mi_flags m
    ON t.hadm_id = m.hadm_id
)
SELECT
  temp_group,
  COUNT(*) AS n_stays,
  ROUND(AVG(mean_temp_c), 2) AS mean_of_means,
  ROUND(APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(50)], 2) AS median_of_means,
  ROUND(APPROX_QUANTILES(mean_temp_c, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(mean_temp_c, 4)[OFFSET(3)], 2) AS iqr_75,
  ROUND(100 * SUM(mi_flag) / COUNT(*), 1) AS mi_rate_percent
FROM joined
GROUP BY temp_group
ORDER BY
  CASE temp_group
    WHEN '<36.0' THEN 1
    WHEN '36.0-37.9' THEN 2
    WHEN '>=38.0' THEN 3
    ELSE 4
  END;