WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) AS age_at_icu_admission,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 37 AND 47
),
spo2_with_rank AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS spo2_value,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    ce.itemid = di.itemid
  JOIN
    patient_ages pa
  ON
    ce.stay_id = pa.stay_id
  WHERE
    LOWER(di.label) = 'spo2'
    AND ce.charttime >= pa.intime
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
)
SELECT
  PERCENTILE_CONT(first_spo2_value, 0.25) OVER () AS q1,
  PERCENTILE_CONT(first_spo2_value, 0.75) OVER () AS q3,
  PERCENTILE_CONT(first_spo2_value, 0.75) OVER () - PERCENTILE_CONT(first_spo2_value, 0.25) OVER () AS iqr
FROM (
  SELECT
    spo2_value AS first_spo2_value
  FROM
    spo2_with_rank
  WHERE
    rn = 1
)
LIMIT 1;