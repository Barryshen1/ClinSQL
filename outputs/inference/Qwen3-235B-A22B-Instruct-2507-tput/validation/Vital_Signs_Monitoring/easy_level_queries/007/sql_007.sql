WITH respiratory_rate_first AS (
  SELECT
    ce.stay_id,
    MIN(ce.charttime) AS first_rr_time
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
    di.label = 'Respiratory Rate'
    AND ce.charttime >= icu.intime
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),
first_rr_values AS (
  SELECT
    ce.valuenum AS rr_value
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    respiratory_rate_first rrf
    ON ce.stay_id = rrf.stay_id AND ce.charttime = rrf.first_rr_time
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
)
SELECT
  STDDEV(rr_value) AS std_first_respiratory_rate
FROM
  first_rr_values;