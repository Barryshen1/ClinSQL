WITH patient_icu AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    i.stay_id,
    i.intime,
    -- Calculate age at ICU admission
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 40 AND 50
),

heart_rate_per_stay AS (
  SELECT
    pi.stay_id,
    AVG(ce.valuenum) AS mean_heart_rate
  FROM
    patient_icu pi
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON
    pi.stay_id = ce.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'heart rate'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    pi.stay_id
)

SELECT
  APPROX_QUANTILES(mean_heart_rate, 100)[OFFSET(50)] AS median_per_stay_mean_heart_rate
FROM
  heart_rate_per_stay;