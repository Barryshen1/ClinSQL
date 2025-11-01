WITH patient_spo2 AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    AVG(CASE WHEN ce.valuenum >= 0 AND ce.valuenum <= 100 THEN ce.valuenum END) AS mean_spo2
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    LOWER(di.label) = 'spo2'
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 73 AND 83
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.subject_id, ce.stay_id
  HAVING
    AVG(ce.valuenum) IS NOT NULL
),
percentile_calc AS (
  SELECT
    SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
  FROM
    patient_spo2
)
SELECT percentile
FROM percentile_calc;