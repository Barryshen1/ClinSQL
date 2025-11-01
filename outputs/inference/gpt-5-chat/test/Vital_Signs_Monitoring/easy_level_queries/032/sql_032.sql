WITH resp_rate AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE
    -- Cohort: Females age between 38 and 48
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    -- Specific patient age 43
    AND p.anchor_age = 43
    -- Respiratory rate itemids
    AND ce.itemid IN (220210, 224690)
    AND ce.valuenum IS NOT NULL
    -- First 24 hours of ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
)
SELECT
  subject_id,
  MAX(valuenum) AS max_resp_rate_first24h
FROM resp_rate
GROUP BY subject_id;