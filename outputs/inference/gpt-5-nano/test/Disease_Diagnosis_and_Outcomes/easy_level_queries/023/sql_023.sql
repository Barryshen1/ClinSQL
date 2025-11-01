SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_hospital_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dld
    ON di.icd_code = dld.icd_code
   AND di.icd_version = dld.icd_version
  WHERE
    UPPER(p.gender) = 'F'
    AND a.dischtime IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- age at admission approx
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 83 AND 93
    -- pneumonia primary diagnosis
    AND LOWER(dld.long_title) LIKE '%pneumonia%'
) AS sub;