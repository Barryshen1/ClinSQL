WITH dbp_max_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    di.category = 'Routine Vital Signs'
    AND LOWER(di.label) LIKE '%diastolic%'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
)
SELECT
  APPROX_QUANTILES(max_dbp, 2)[OFFSET(1)] AS median_max_dbp
FROM
  dbp_max_per_stay
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON dbp_max_per_stay.stay_id = icu.stay_id
JOIN
  physionet-data.mimiciv_3_1_hosp.patients pat
  ON icu.subject_id = pat.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 71 AND 81;