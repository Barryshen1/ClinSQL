WITH cohort AS (
  SELECT p.subject_id, p.anchor_age, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),
rr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
),
max_rr_per_stay AS (
  SELECT c.stay_id,
         MAX(ce.valuenum) AS max_resp_rate
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  INNER JOIN rr_items ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND c.outtime
  GROUP BY c.stay_id
)
SELECT STDDEV_POP(max_resp_rate) AS sd_max_resp_rate
FROM max_rr_per_stay;