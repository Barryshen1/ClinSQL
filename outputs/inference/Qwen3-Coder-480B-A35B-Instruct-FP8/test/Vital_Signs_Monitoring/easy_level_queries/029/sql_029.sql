WITH first_spo2 AS (
  SELECT
    ce.subject_id,
    ce.valuenum AS spo2,
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE
    LOWER(di.label) LIKE '%spo2%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(spo2, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(spo2, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(spo2, 100)[OFFSET(25)] AS iqr
FROM
  first_spo2
WHERE
  rn = 1;