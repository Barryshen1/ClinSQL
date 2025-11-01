WITH rate_by_stay AS (
  SELECT
    i.subject_id,
    i.stay_id,
    MAX(ce.valuenum) AS max_resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
  GROUP BY i.subject_id, i.stay_id
)
SELECT
  MIN(r.max_resp_rate) AS min_of_max_respiratory_rate
FROM rate_by_stay r
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = r.subject_id
WHERE p.gender = 'Male'
  AND p.anchor_age BETWEEN 35 AND 45
  AND r.max_resp_rate IS NOT NULL;