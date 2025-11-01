WITH icu_patients AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
temp_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN icu_patients AS ip
    ON ip.subject_id = ce.subject_id
   AND ip.hadm_id = ce.hadm_id
   AND ip.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%temperature%'
    AND ce.charttime >= ip.intime
    AND ce.charttime < TIMESTAMP_ADD(ip.intime, INTERVAL 24 HOUR)
),
temp_values AS (
  SELECT
    te.subject_id,
    te.hadm_id,
    te.stay_id,
    CASE
      WHEN te.valueuom IS NULL THEN NULL
      WHEN UPPER(te.valueuom) IN ('C', 'CELSIUS') THEN te.valuenum * 9.0 / 5.0 + 32.0
      WHEN UPPER(te.valueuom) IN ('F', 'FAHRENHEIT') THEN te.valuenum
      ELSE NULL
    END AS temp_f
  FROM temp_events te
  WHERE te.valuenum IS NOT NULL
)
SELECT
  (APPROX_QUANTILES(temp_f, 100))[OFFSET(75)] AS p75_temp_f
FROM temp_values
LIMIT 1;