WITH rr_per_stay AS (
  -- Compute max respiratory rate per ICU stay
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),

cohort_stays AS (
  -- Identify ICU stays for male patients aged 35–45
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
)

-- Find the overall minimum of the per-stay max respiratory rates
SELECT
  MIN(rr.max_rr) AS min_of_max_rr
FROM
  rr_per_stay rr
  JOIN cohort_stays cs
    ON rr.stay_id = cs.stay_id;