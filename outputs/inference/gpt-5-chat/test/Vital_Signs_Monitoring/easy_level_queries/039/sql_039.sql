WITH resp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
    AND linksto = 'chartevents'
),
first_resp_per_stay AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    MIN_BY(ce.valuenum, ce.charttime) AS first_resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN resp_itemids di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND ce.valuenum IS NOT NULL
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id
)
SELECT
  PERCENTILE_CONT(first_resp_rate, 0.25) OVER() AS p25_first_resp_rate
FROM first_resp_per_stay;