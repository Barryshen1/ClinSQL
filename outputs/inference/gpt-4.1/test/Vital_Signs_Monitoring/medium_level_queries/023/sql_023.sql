WITH female_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 62 AND 72
),

temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND LOWER(unitname) = 'c'
),

creat_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(category) = 'chemistry'
),

temp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN temp_items ti ON ce.itemid = ti.itemid
    JOIN female_icu fi ON ce.stay_id = fi.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fi.intime AND DATETIME_ADD(fi.intime, INTERVAL 24 HOUR)
),

creat_measurements AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    fi.stay_id,
    le.charttime,
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN creat_items ci ON le.itemid = ci.itemid
    JOIN female_icu fi ON le.hadm_id = fi.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN fi.intime AND DATETIME_ADD(fi.intime, INTERVAL 48 HOUR)
),

creat_baseline AS (
  -- Baseline creatinine: first value in first 24h of ICU stay
  SELECT
    cm.stay_id,
    MIN(cm.charttime) AS baseline_time
  FROM creat_measurements cm
  WHERE cm.charttime BETWEEN
    (SELECT intime FROM female_icu WHERE stay_id = cm.stay_id)
    AND DATETIME_ADD((SELECT intime FROM female_icu WHERE stay_id = cm.stay_id), INTERVAL 24 HOUR)
  GROUP BY cm.stay_id
),

creat_baseline_value AS (
  SELECT
    cm.stay_id,
    cm.valuenum AS baseline_creat
  FROM creat_measurements cm
  JOIN creat_baseline cb
    ON cm.stay_id = cb.stay_id AND cm.charttime = cb.baseline_time
),

creat_max_48h AS (
  SELECT
    stay_id,
    MAX(valuenum) AS max_creat_48h
  FROM creat_measurements
  GROUP BY stay_id
),

aki_status AS (
  SELECT
    cbv.stay_id,
    CASE
      WHEN cm48.max_creat_48h - cbv.baseline_creat >= 0.3 THEN 1
      ELSE 0
    END AS aki
  FROM creat_baseline_value cbv
  JOIN creat_max_48h cm48 ON cbv.stay_id = cm48.stay_id
),

temp_with_aki AS (
  SELECT
    tm.subject_id,
    tm.hadm_id,
    tm.stay_id,
    tm.charttime,
    tm.valuenum,
    CASE
      WHEN tm.valuenum < 36.0 THEN '<36.0'
      WHEN tm.valuenum >= 36.0 AND tm.valuenum < 38.0 THEN '36.0–37.9'
      WHEN tm.valuenum >= 38.0 THEN '≥38.0'
      ELSE NULL
    END AS temp_category,
    ak.aki
  FROM temp_measurements tm
  LEFT JOIN aki_status ak ON tm.stay_id = ak.stay_id
  WHERE tm.valuenum IS NOT NULL
    AND (
      tm.valuenum < 36.0 OR
      (tm.valuenum >= 36.0 AND tm.valuenum < 38.0) OR
      tm.valuenum >= 38.0
    )
)

SELECT
  temp_category,
  COUNT(*) AS n_measurements,
  ROUND(AVG(valuenum), 2) AS mean_temp,
  ROUND(APPROX_QUANTILES(valuenum, 2)[OFFSET(1)], 2) AS median_temp,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 2) AS iqr_temp_low,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 2) AS iqr_temp_high,
  ROUND(SUM(CASE WHEN aki = 1 THEN 1 ELSE 0 END) / COUNTIF(aki IS NOT NULL), 4) AS aki_rate
FROM temp_with_aki
GROUP BY temp_category
ORDER BY
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
    ELSE 4
  END;