WITH respiratory_rate_per_stay AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_respiratory_rate
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    LOWER(di.label) LIKE '%respiratory rate%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 5 AND 60  -- Physiologically plausible range
  GROUP BY
    ce.stay_id
)
SELECT
  PERCENTILE_CONT(mean_respiratory_rate, 0.75) OVER () AS p75_mean_respiratory_rate
FROM
  respiratory_rate_per_stay
LIMIT 1;