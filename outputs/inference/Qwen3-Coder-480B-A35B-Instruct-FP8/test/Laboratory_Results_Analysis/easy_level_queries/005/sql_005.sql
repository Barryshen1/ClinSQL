WITH first_sodium AS (
  SELECT
    icu.stay_id,
    le.hadm_id,
    le.subject_id,
    le.valuenum AS sodium_value,
    ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY le.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_icu.icustays AS icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents AS le
    ON icu.hadm_id = le.hadm_id
    AND le.charttime >= icu.intime
    AND le.charttime <= icu.outtime
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS dlab
    ON le.itemid = dlab.itemid
  WHERE
    pat.gender = 'M'
    AND LOWER(dlab.label) LIKE '%sodium%'
    AND le.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(sodium_value, 4)[OFFSET(3)] - APPROX_QUANTILES(sodium_value, 4)[OFFSET(1)] AS IQR
FROM
  first_sodium
WHERE
  rn = 1;