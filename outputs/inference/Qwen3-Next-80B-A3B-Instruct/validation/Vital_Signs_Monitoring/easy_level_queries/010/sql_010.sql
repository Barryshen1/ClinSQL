WITH dbp_max_per_stay AS (
  SELECT
    ie.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.icustays ie
    ON ce.stay_id = ie.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  WHERE
    di.label IN ('Diastolic Blood Pressure', 'DBP', 'BP Diastolic')
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY
    ie.stay_id
)
SELECT
  APPROX_QUANTILES(max_dbp, 2)[OFFSET(1)] AS median_per_stay_max_dbp
FROM
  dbp_max_per_stay;