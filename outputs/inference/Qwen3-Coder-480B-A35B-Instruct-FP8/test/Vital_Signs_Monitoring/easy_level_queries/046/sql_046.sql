WITH first_spo2 AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS spo2,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'spo2'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
),
icu_patients AS (
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pat.subject_id = icu.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
)
SELECT
  APPROX_QUANTILES(spo2, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(spo2, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(spo2, 4)[OFFSET(3)] - APPROX_QUANTILES(spo2, 4)[OFFSET(1)] AS iqr
FROM
  first_spo2
JOIN
  icu_patients
  ON first_spo2.stay_id = icu_patients.stay_id
WHERE
  rn = 1;