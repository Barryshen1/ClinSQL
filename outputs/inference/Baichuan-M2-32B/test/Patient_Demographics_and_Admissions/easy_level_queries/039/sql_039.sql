WITH cohort AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    TIMESTAMP_DIFF(icu.outtime, icu.intime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_icu.icustays AS icu
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS p
    ON icu.subject_id = p.subject_id
  INNER JOIN (
    SELECT DISTINCT
      d1.subject_id,
      d1.hadm_id
    FROM
      physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS d1
    INNER JOIN
      physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d2
      ON d1.icd_code = d2.icd_code
      AND d1.icd_version = d2.icd_version
    WHERE
      d2.icd_code BETWEEN 'J12' AND 'J18'  -- Specific ICD-10 codes for pneumonia
      AND d1.icd_version = 10  -- Ensure ICD-10 codes
  ) AS pneumonia
    ON icu.subject_id = pneumonia.subject_id
    AND icu.hadm_id = pneumonia.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53  -- Age range 43-53
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.subject_id
    ORDER BY icu.intime
  ) = 1  -- First ICU stay per patient
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los
FROM
  cohort;