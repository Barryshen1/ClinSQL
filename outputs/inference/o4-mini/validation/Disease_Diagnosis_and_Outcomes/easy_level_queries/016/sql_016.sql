WITH target_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- LOS in days as fractional
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  -- Age and gender filter
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Admission must have pneumonia
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
    -- Admission must have COPD (obstructive pulmonary disease)
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%obstructive%'
    )
)
SELECT
  -- 75th percentile of hospital LOS in days
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile_days
FROM
  target_admissions;