with base as (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.los,
    p.subject_id,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 71 AND 81
),

-- Part 2: compute per-stay average temperature within first 48 hours
temp_by_stay AS (
  SELECT
    b.stay_id,
    b.hadm_id,
    AVG(cev.valuenum) AS avg_temp
  FROM base AS b
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS cev
    ON cev.stay_id = b.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = cev.itemid
  WHERE LOWER(di.label) LIKE '%temperature%'          -- temperature related measurements
    AND cev.charttime >= b.intime
    AND cev.charttime < TIMESTAMP_ADD(b.intime, INTERVAL 48 HOUR)
    AND cev.valuenum IS NOT NULL
  GROUP BY b.stay_id, b.hadm_id
),

-- Part 3: classify per-stay temps into the 3 categories
categorized AS (
  SELECT
    t.stay_id,
    t.hadm_id,
    t.avg_temp,
    CASE
      WHEN t.avg_temp < 36.0 THEN '<36.0'
      WHEN t.avg_temp >= 36.0 AND t.avg_temp <= 37.9 THEN '36.0-37.9'
      WHEN t.avg_temp >= 38.0 THEN '>=38.0'
      ELSE NULL
    END AS temp_cat
  FROM temp_by_stay AS t
  WHERE t.avg_temp IS NOT NULL
),

-- Part 4: MI event counts per admission (hadm_id) for the stays
mi_per_admission AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS mi_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'
  GROUP BY d.hadm_id
),

-- Part 5: assemble per-stay MI rate and link to icustays LOS
mi_per_stay AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    c.avg_temp,
    c.temp_cat,
    i.los,
    COALESCE(m.mi_count, 0) AS mi_count
  FROM categorized AS c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.stay_id = c.stay_id
  LEFT JOIN mi_per_admission AS m
    ON m.hadm_id = c.hadm_id
),

-- Part 6: final aggregation by temperature category
final AS (
  SELECT
    temp_cat,
    COUNT(*) AS n_stays,
    AVG(avg_temp) AS mean_temp,
    APPROX_QUANTILES(avg_temp, 4)[OFFSET(2)] AS median_temp,  -- approximate median
    (APPROX_QUANTILES(avg_temp, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_temp, 4)[OFFSET(1)]) AS iqr_approx,
    AVG(mi_count / NULLIF(los, 0)) * 24.0 AS mi_rate_per_day
  FROM mi_per_stay
  GROUP BY temp_cat
)

SELECT
  temp_cat,
  n_stays,
  mean_temp,
  median_temp,
  iqr_approx AS iqr,
  mi_rate_per_day
FROM final
ORDER BY temp_cat;