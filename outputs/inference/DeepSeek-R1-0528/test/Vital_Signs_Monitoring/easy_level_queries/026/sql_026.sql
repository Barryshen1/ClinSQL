WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
)
SELECT
  MIN(ce.valuenum) AS min_resp_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN cohort
  ON ce.stay_id = cohort.stay_id
WHERE
  ce.itemid IN (220210, 224688)  -- Respiratory rate item IDs
  AND ce.valuenum IS NOT NULL    -- Exclude non-numeric values
  AND ce.valuenum > 0            -- Ensure valid respiratory rate
  AND ce.charttime >= cohort.intime
  AND ce.charttime <= DATETIME_ADD(cohort.intime, INTERVAL 24 HOUR);