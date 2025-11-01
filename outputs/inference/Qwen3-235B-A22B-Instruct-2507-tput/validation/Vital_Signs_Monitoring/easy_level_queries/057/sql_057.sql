WITH resp_rate_max_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_resp_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays ce_stay
  ON
    p.subject_id = ce_stay.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON
    ce_stay.stay_id = ce.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 35
    AND p.anchor_age <= 45
    AND LOWER(di.label) = 'respiratory rate'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
)
SELECT
  MIN(max_resp_rate) AS min_of_max_resp_rate
FROM
  resp_rate_max_per_stay;