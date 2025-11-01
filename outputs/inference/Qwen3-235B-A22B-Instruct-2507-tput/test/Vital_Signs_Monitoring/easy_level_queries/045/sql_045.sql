WITH respiratory_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
),
first_rr_per_stay AS (
  SELECT
    ce.stay_id,
    ce.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN respiratory_rate_items rri ON ce.itemid = rri.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime <= ie.outtime
)
SELECT
  STDDEV(valuenum) AS sd_first_respiratory_rate
FROM first_rr_per_stay
WHERE rn = 1;