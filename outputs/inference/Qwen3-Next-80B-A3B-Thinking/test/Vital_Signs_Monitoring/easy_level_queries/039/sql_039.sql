WITH eligible_stays AS (
  SELECT
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 51 AND 61
),
first_rr AS (
  SELECT
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    eligible_stays es ON c.stay_id = es.stay_id
  WHERE
    c.itemid = 618
    AND c.charttime >= es.intime
    AND c.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS percentile_25
FROM
  first_rr
WHERE
  rn = 1;