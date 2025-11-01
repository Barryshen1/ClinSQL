WITH ecg_patients AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS distinct_ecg_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code
    AND proc.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      LOWER(d.long_title) LIKE '%ecg%'
      OR LOWER(d.long_title) LIKE '%electrocardiogram%'
      OR LOWER(d.long_title) LIKE '%telemetry%'
    )
  GROUP BY p.subject_id
)
SELECT
  APPROX_QUANTILES(distinct_ecg_proc_count, 100)[OFFSET(25)] AS percentile_25_distinct_ecg_procs
FROM ecg_patients;