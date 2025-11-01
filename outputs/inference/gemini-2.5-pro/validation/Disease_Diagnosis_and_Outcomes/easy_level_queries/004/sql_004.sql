WITH primary_dka_hhs_admissions AS (
  -- Find hospital admissions where the primary diagnosis is DKA or HHS
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE
    -- Filter for primary diagnosis
    dx.seq_num = 1
    -- Use long_title to identify DKA or HHS across ICD-9 and ICD-10
    AND (
      LOWER(d.long_title) LIKE '%ketoacidosis%'
      OR LOWER(d.long_title) LIKE '%hyperosmolar%'
    )
)
SELECT
  -- Calculate the 25th percentile of the hospital length of stay
  APPROX_QUANTILES(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0, 100)[OFFSET(25)] AS los_p25_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
INNER JOIN
  primary_dka_hhs_admissions AS pdh
  ON a.hadm_id = pdh.hadm_id
WHERE
  -- Filter for male patients
  p.gender = 'M'
  -- Filter for age at admission between 73 and 83 years
  AND (p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 73 AND 83;