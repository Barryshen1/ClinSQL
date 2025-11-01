SELECT
  APPROX_QUANTILES(mean_temp, 100)[OFFSET(75)] AS temp_75th_percentile
FROM (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_temp
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON
    ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND LOWER(di.label) LIKE '%temperature%'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
) AS stay_averages;