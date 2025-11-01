WITH hadm_with_both_diagnoses AS (
  -- Find hospital admissions that have a diagnosis for both Pneumonia and COPD
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%pneumonia%'
    OR LOWER(d_dx.long_title) LIKE '%chronic obstructive pulmonary disease%'
  GROUP BY
    hadm_id
  HAVING
    -- Ensure both diagnosis types are present for the admission
    COUNT(DISTINCT
      CASE
        WHEN LOWER(d_dx.long_title) LIKE '%pneumonia%' THEN 'pneumonia'
        WHEN LOWER(d_dx.long_title) LIKE '%chronic obstructive pulmonary disease%' THEN 'copd'
      END
    ) = 2
)

SELECT
  -- Calculate the 75th percentile of the hospital length of stay
  APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0, 100)[OFFSET(75)] AS los_days_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  hadm_with_both_diagnoses
  ON adm.hadm_id = hadm_with_both_diagnoses.hadm_id
WHERE
  -- Filter for males
  pat.gender = 'M'
  -- Filter for the specified age range at the time of admission
  AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 68 AND 78;