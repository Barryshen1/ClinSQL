WITH cohort AS (
  SELECT
    ie.stay_id,
    MAX(ce.valuenum) AS max_hr
  FROM
    physionet-data.mimiciv_3_1_icu.icustays ie
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON ie.stay_id = ce.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ie.stay_id
)
SELECT
  APPROX_QUANTILES(max_hr, 4)[OFFSET(3)] - APPROX_QUANTILES(max_hr, 4)[OFFSET(1)] AS iqr_max_hr
FROM
  cohort;