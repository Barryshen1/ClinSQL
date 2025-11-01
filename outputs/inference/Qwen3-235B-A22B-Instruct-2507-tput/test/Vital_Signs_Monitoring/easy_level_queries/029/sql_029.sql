WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age >= 62
    AND anchor_age <= 72
),
spo2_first AS (
  SELECT
    ce.subject_id,
    MIN(ce.charttime) AS first_spo2_time
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN male_patients mp ON ce.subject_id = mp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'spo2'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id
),
first_spo2_values AS (
  SELECT
    ce.valuenum AS first_spo2_value
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN spo2_first s ON ce.subject_id = s.subject_id AND ce.charttime = s.first_spo2_time
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'spo2'
    AND ce.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(first_spo2_value, 0.75) OVER () - PERCENTILE_CONT(first_spo2_value, 0.25) OVER () AS iqr
FROM first_spo2_values
LIMIT 1;