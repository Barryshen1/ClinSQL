WITH min_creatinine_per_admission AS (
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS nadir_creatinine
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON le.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    dl.label = 'creatinine'
    AND le.valuenum IS NOT NULL
    AND pat.gender = 'M'
  GROUP BY
    le.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(3)] - APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(1)] AS iqr
FROM
  min_creatinine_per_admission;