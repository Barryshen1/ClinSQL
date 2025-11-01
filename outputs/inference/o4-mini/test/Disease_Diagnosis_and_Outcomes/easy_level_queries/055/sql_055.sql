WITH aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
   AND d.seq_num    = 1  -- primary diagnosis
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
    ON d.icd_code    = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND LOWER(dicd.long_title) LIKE '%acute kidney injury%'
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days
FROM
  aki_admissions;