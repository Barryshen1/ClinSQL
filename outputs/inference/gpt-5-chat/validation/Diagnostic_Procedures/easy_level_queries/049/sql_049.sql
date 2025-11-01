SELECT
  STDDEV_SAMP(proc_count) AS sd_distinct_ecg_codes_per_patient
FROM (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(dpr.long_title) LIKE '%ecg%'
        OR LOWER(dpr.long_title) LIKE '%electrocardiogram%'
        OR LOWER(dpr.long_title) LIKE '%telemetry%'
  GROUP BY p.subject_id
);