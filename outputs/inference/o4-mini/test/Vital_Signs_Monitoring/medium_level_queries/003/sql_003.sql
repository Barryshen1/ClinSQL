WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),
temp_measurements AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    AVG(ce.valuenum) AS avg_temp48
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.subject_id = ce.subject_id
     AND c.hadm_id    = ce.hadm_id
     AND c.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%temp%'
    AND LOWER(di.unitname) IN ('c', 'cel')
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    c.stay_id,
    c.hadm_id
),
mi_flags AS (
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 9  AND icd_code LIKE '410%')
          OR (icd_version = 10 AND icd_code LIKE 'I21%')
        THEN 1
        ELSE 0
      END
    ) AS mi_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
stay_summary AS (
  SELECT
    tm.stay_id,
    tm.avg_temp48,
    CASE
      WHEN tm.avg_temp48 < 36.0 THEN '<36.0'
      WHEN tm.avg_temp48 < 38.0 THEN '36.0-37.9'
      ELSE '>=38.0'
    END AS temp_category,
    COALESCE(m.mi_flag, 0) AS mi_flag
  FROM
    temp_measurements AS tm
    LEFT JOIN mi_flags AS m
      ON tm.hadm_id = m.hadm_id
),
stats AS (
  SELECT
    temp_category,
    APPROX_QUANTILES(avg_temp48, 4) AS quants,
    AVG(avg_temp48) AS mean_temp,
    AVG(mi_flag)     AS mi_rate
  FROM
    stay_summary
  GROUP BY
    temp_category
)
SELECT
  temp_category,
  ROUND(mean_temp, 2)              AS mean_temp,
  ROUND(quants[OFFSET(1)], 2)      AS q1_temp,
  ROUND(quants[OFFSET(2)], 2)      AS median_temp,
  ROUND(quants[OFFSET(3)], 2)      AS q3_temp,
  ROUND(quants[OFFSET(3)] - quants[OFFSET(1)], 2) AS iqr_temp,
  ROUND(mi_rate, 3)                AS mi_rate
FROM
  stats
ORDER BY
  temp_category;