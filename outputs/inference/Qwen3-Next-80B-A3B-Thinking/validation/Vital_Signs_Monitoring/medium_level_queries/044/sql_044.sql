WITH icu_patients AS (
  SELECT
    i.stay_id,
    i.intime,
    p.gender,
    DATE_DIFF(i.intime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND DATE_DIFF(i.intime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 81 AND 91
),
systolic_averages AS (
  SELECT
    i.stay_id,
    AVG(c.valuenum) AS avg_sbp
  FROM icu_patients i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE c.itemid = 220050
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY i.stay_id
)
SELECT
  COUNTIF(avg_sbp <= 150) / COUNT(*) AS percentile
FROM systolic_averages;