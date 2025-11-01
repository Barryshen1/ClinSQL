WITH respiratory_per_stay AS (
  SELECT
    i.subject_id,
    i.stay_id,
    MAX(c.valuenum) AS max_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE
    d.label = 'Respiratory Rate'
    AND c.valuenum IS NOT NULL
  GROUP BY
    i.subject_id, i.stay_id
),
patient_max_rr AS (
  SELECT
    subject_id,
    MAX(max_rr) AS patient_max_rr
  FROM
    respiratory_per_stay
  GROUP BY
    subject_id
)
SELECT
  STDDEV(pmr.patient_max_rr) AS sd_max_rr
FROM
  patient_max_rr pmr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON pmr.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73;