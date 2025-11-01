WITH rr_per_stay AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(c.valuenum) AS mean_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` s
    ON c.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON c.subject_id = p.subject_id
  WHERE
    -- Identify respiratory-rate related items by label
    LOWER(d.label) LIKE '%resp%'
    -- use numeric values only and a reasonable physiologic range
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 3 AND 60
    -- female patients aged 39-49 inclusive
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
)
SELECT
  -- 75th percentile (approximate) of mean respiratory rate per ICU stay
  APPROX_QUANTILES(mean_rr, 5)[OFFSET(3)] AS rr_75th_percentile
FROM
  rr_per_stay
WHERE
  mean_rr IS NOT NULL;