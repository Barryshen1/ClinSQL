WITH per_stay AS (
  SELECT
    si.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS si
    ON ce.subject_id = si.subject_id
   AND ce.hadm_id = si.hadm_id
   AND ce.stay_id = si.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 5 AND 60
  GROUP BY si.stay_id
)
SELECT
  PERCENTILE_CONT(mean_rr, 0.75) OVER () AS percentile_75
FROM per_stay
LIMIT 1;