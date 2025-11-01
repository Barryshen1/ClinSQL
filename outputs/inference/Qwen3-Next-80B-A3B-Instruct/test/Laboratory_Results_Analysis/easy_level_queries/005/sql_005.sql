WITH first_sodium_per_stay AS (
  SELECT
    i.stay_id,
    MIN(c.charttime) AS first_charttime,
    MIN(c.valuenum) AS first_sodium_valuenum  -- We take the value at the earliest charttime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND d.label = 'Sodium'
    AND c.valuenum IS NOT NULL
  GROUP BY
    i.stay_id
)
SELECT
  PERCENTILE_CONT(first_sodium_valuenum, 0.25) OVER () AS q1,
  PERCENTILE_CONT(first_sodium_valuenum, 0.75) OVER () AS q3,
  PERCENTILE_CONT(first_sodium_valuenum, 0.75) OVER () - PERCENTILE_CONT(first_sodium_valuenum, 0.25) OVER () AS iqr
FROM
  first_sodium_per_stay
LIMIT 1;