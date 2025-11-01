WITH dbp_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
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
    LOWER(di.label) LIKE '%diastolic blood pressure%' 
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY
    ce.stay_id
)
SELECT
  APPROX_QUANTILES(max_dbp, 100)[OFFSET(50)] AS median_max_dbp
FROM
  dbp_per_stay;