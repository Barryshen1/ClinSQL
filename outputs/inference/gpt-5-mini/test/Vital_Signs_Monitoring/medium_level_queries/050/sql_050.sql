WITH hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%heart rate%'
    OR LOWER(label) LIKE '%pulse%'
    OR abbreviation = 'HR'
),

first24_avg_hr AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = icu.stay_id
  JOIN hr_items h
    ON ce.itemid = h.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 300
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id, p.anchor_age
)

SELECT
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_hr < 110 THEN 1 ELSE 0 END) AS count_avg_lt_110,
  SUM(CASE WHEN avg_hr = 110 THEN 1 ELSE 0 END) AS count_avg_eq_110,
  100.0 * (
    SUM(CASE WHEN avg_hr < 110 THEN 1 ELSE 0 END)
    + 0.5 * SUM(CASE WHEN avg_hr = 110 THEN 1 ELSE 0 END)
  ) / COUNT(*) AS percentile_of_110
FROM first24_avg_hr;