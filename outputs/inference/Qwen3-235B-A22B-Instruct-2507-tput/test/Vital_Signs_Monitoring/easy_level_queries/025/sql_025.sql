SELECT
  APPROX_QUANTILES(mean_rr, 1000)[OFFSET(750)] AS rr_75th_percentile
FROM (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    ce.subject_id = p.subject_id
  WHERE
    di.label = 'Respiratory Rate'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
);