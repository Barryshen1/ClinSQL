WITH min_temps AS (
  SELECT
    icu.stay_id,
    MIN(ce.valuenum) AS min_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    ce.itemid = 223761
    AND p.gender = 'M'
    AND EXTRACT(YEAR FROM icu.intime) - (p.anchor_year - p.anchor_age) BETWEEN 74 AND 84
  GROUP BY
    icu.stay_id
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY min_temp) AS median_min_temp
FROM
  min_temps;