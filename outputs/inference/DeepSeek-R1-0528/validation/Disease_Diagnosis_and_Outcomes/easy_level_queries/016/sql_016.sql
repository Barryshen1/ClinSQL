WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute LOS in days (whole days)
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    -- Filter for age 68-78 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    -- Ensure admission has both pneumonia and COPD diagnoses
    AND adm.hadm_id IN (
      -- Pneumonia diagnoses
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code
        AND diag.icd_version = d.icd_version
      WHERE d.long_title LIKE '%pneumonia%'
    )
    AND adm.hadm_id IN (
      -- COPD diagnoses
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code
        AND diag.icd_version = d.icd_version
      WHERE 
        d.long_title LIKE '%chronic obstructive pulmonary%' OR
        d.long_title LIKE '%COPD%' OR
        d.long_title LIKE '%emphysema%' OR
        d.long_title LIKE '%chronic bronchitis%'
    )
)
-- Calculate 75th percentile LOS using BigQuery-compatible function
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM cohort;