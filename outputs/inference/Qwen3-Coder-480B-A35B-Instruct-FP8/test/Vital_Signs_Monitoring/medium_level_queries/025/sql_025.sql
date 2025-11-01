WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age,
    SAFE_CAST(SPLIT(pat.anchor_year_group, ' - ')[OFFSET(0)] AS INT64) AS anchor_year_start
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND (SAFE_CAST(SPLIT(pat.anchor_year_group, ' - ')[OFFSET(0)] AS INT64) + pat.anchor_age) BETWEEN 82 AND 92
),

temperature_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%temperature%'
    AND (LOWER(label) LIKE '%celsius%' OR LOWER(label) LIKE '%°c%')
),

first_24hr_temperatures AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN
    temperature_items ti
  ON
    ce.itemid = ti.itemid
  JOIN
    cohort coh
  ON
    ce.stay_id = coh.stay_id
  WHERE
    ce.charttime >= coh.intime
    AND ce.charttime <= DATETIME_ADD(coh.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45  -- Physiological range
  GROUP BY
    ce.stay_id
),

percentiles AS (
  SELECT
    avg_temp,
    PERCENT_RANK() OVER (ORDER BY avg_temp) AS percentile_rank
  FROM
    first_24hr_temperatures
)

SELECT
  MAX(CASE WHEN avg_temp <= 37.5 THEN percentile_rank ELSE NULL END) AS percentile_of_37_5
FROM
  percentiles;