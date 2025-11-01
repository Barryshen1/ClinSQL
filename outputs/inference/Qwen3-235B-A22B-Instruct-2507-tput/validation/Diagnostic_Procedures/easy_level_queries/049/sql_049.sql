SELECT STDDEV(ecg_procedure_count) AS sd_distinct_ecg_procedures_per_patient
FROM (
  SELECT p.subject_id, COUNT(DISTINCT pi.icd_code) AS ecg_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON p.subject_id = pi.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(d.long_title) LIKE '%ecg%'
    OR LOWER(d.long_title) LIKE '%electrocardiogram%'
    OR LOWER(d.long_title) LIKE '%telemetry%'
  GROUP BY p.subject_id
) sub;