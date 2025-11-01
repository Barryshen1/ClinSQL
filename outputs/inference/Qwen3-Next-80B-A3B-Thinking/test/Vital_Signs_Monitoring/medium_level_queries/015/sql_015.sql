WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'emergency'
),
sbp_values AS (
  SELECT
    e.stay_id,
    MAX(c.valuenum) AS max_sbp
  FROM
    eligible_patients e
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON e.stay_id = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%systolic%'
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
  GROUP BY
    e.stay_id
)
SELECT
  PERCENTILE_CONT(max_sbp, 0.75) OVER () AS percentile_75
FROM
  sbp_values
LIMIT 1;