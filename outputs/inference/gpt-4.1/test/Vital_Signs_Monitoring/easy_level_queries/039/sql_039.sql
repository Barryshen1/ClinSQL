WITH female_51_61 AS (
  SELECT
    p.subject_id,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN female_51_61 f
    ON i.subject_id = f.subject_id
),
resp_rate_items AS (
  -- Itemids for respiratory rate in MIMIC-IV
  SELECT 220210 AS itemid UNION ALL
  SELECT 224690 AS itemid
),
first_resp_rate AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    MIN(c.charttime) AS first_charttime
  FROM
    icu_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id
    AND s.hadm_id = c.hadm_id
    AND s.stay_id = c.stay_id
    AND c.charttime >= s.intime
    AND c.charttime <= s.outtime
  INNER JOIN resp_rate_items rri
    ON c.itemid = rri.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND c.valuenum > 0
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id
),
first_resp_rate_value AS (
  SELECT
    fr.subject_id,
    fr.hadm_id,
    fr.stay_id,
    c.valuenum AS first_resp_rate
  FROM
    first_resp_rate fr
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON fr.subject_id = c.subject_id
    AND fr.hadm_id = c.hadm_id
    AND fr.stay_id = c.stay_id
    AND c.charttime = fr.first_charttime
  INNER JOIN resp_rate_items rri
    ON c.itemid = rri.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND c.valuenum > 0
)
SELECT
  PERCENTILE_CONT(first_resp_rate, 0.25) OVER () AS resp_rate_25th_percentile
FROM
  first_resp_rate_value
;