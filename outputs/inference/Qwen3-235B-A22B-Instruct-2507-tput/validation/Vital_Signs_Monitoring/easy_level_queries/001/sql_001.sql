WITH map_first AS (
  SELECT
    ce.stay_id,
    FIRST_VALUE(ce.valuenum) OVER (
      PARTITION BY ce.stay_id
      ORDER BY ce.charttime ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_map
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    LOWER(di.label) = 'mean blood pressure'
    AND ce.charttime >= icu.intime
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
)
SELECT
  APPROX_QUANTILES(first_map, 1000)[OFFSET(750)] - APPROX_QUANTILES(first_map, 1000)[OFFSET(250)] AS iqr_map
FROM
  map_first;