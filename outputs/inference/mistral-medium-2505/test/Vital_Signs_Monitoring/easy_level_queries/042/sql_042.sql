WITH female_patients_63_73 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),

respiratory_rate_itemid AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label LIKE '%Respiratory Rate%'
    OR abbreviation LIKE '%RR%'
),

max_respiratory_rate_per_stay AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    MAX(ce.valuenum) AS max_respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    respiratory_rate_itemid rri ON ce.itemid = rri.itemid
  JOIN
    female_patients_63_73 fp ON ce.subject_id = fp.subject_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude unrealistic values (e.g., 0 or negative)
  GROUP BY
    ce.subject_id, ce.stay_id
)

SELECT
  STDDEV(max_respiratory_rate) AS sd_max_respiratory_rate
FROM
  max_respiratory_rate_per_stay
WHERE
  max_respiratory_rate IS NOT NULL;