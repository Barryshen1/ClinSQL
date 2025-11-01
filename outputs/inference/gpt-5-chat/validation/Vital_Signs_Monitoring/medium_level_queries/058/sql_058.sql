WITH sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(label) LIKE '%blood pressure%'
    AND linksto = 'chartevents'
),
first24h_sbp AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sbp_items si
    ON ce.itemid = si.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
  GROUP BY ce.stay_id
),
percentile_calc AS (
  SELECT
    COUNT(*) AS n_total,
    SUM(CASE WHEN avg_sbp <= 120 THEN 1 ELSE 0 END) AS n_le_120
  FROM first24h_sbp
)
SELECT
  n_total,
  n_le_120,
  ROUND(100.0 * n_le_120 / n_total,2) AS percentile_120_sbp
FROM percentile_calc;