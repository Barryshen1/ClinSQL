WITH nadir_creat AS (
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS min_creat
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  WHERE
    LOWER(dli.label) = 'creatinine'
    AND p.gender = 'M'
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.hadm_id
)
SELECT
  APPROX_QUANTILES(min_creat, 1000)[OFFSET(250)] AS iqr_lower, -- 25th percentile
  APPROX_QUANTILES(min_creat, 1000)[OFFSET(750)] AS iqr_upper  -- 75th percentile
FROM
  nadir_creat;