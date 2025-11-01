WITH eligible_subjects AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
)
SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
JOIN `physionet-data.mimiciv_3_1_icu.icustays` isty
  ON ce.subject_id = isty.subject_id
  AND ce.hadm_id = isty.hadm_id
  AND ce.stay_id = isty.stay_id
JOIN eligible_subjects es
  ON ce.subject_id = es.subject_id
WHERE LOWER(di.label) LIKE '%respiratory rate%'
  AND ce.valuenum IS NOT NULL
  AND ce.charttime IS NOT NULL
  -- ICU day 2 or later: difference from ICU start intime is at least 1 day
  AND TIMESTAMP_DIFF(ce.charttime, isty.intime, DAY) >= 1
  -- Ensure the measurement occurred during the ICU stay
  AND ce.charttime >= isty.intime
  AND ce.charttime <= isty.outtime;