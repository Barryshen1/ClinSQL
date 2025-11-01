WITH sbp_per_stay AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    i.hadm_id,
    AVG(ce.valuenum) AS sbp_avg
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    i.intime <= ce.charttime
    AND ce.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND LOWER(di.label) LIKE '%systolic%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.subject_id,
    ce.stay_id,
    i.hadm_id
)

SELECT
  CASE
    WHEN sbp_avg < 140 THEN '<140'
    WHEN sbp_avg BETWEEN 140 AND 159 THEN '140-159'
    WHEN sbp_avg >= 160 THEN '>=160'
  END AS sbp_category,
  COUNT(DISTINCT subject_id) AS unique_patients
FROM sbp_per_stay
GROUP BY sbp_category
ORDER BY sbp_category;