WITH ecg_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    proc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON proc.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code
    AND proc.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      dicd.long_title LIKE '%ECG%'
      OR dicd.long_title LIKE '%electrocardiogram%'
      OR dicd.long_title LIKE '%telemetry%'
      OR dicd.long_title LIKE '%cardiac monitoring%'
    )
),
counts_per_patient AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM ecg_procedures
  GROUP BY subject_id
)
SELECT
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25
FROM counts_per_patient;