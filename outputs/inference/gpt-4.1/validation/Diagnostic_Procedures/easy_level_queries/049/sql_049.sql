WITH ecg_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ecg%'
     OR LOWER(long_title) LIKE '%electrocardiogram%'
     OR LOWER(long_title) LIKE '%telemetry%'
),
male_81_91 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 81 AND 91
),
patient_ecg_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS num_distinct_ecg_codes
  FROM male_81_91 p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  LEFT JOIN ecg_codes ecg
    ON pr.icd_code = ecg.icd_code AND pr.icd_version = ecg.icd_version
  WHERE ecg.icd_code IS NOT NULL
  GROUP BY p.subject_id
)
SELECT
  STDDEV(IFNULL(num_distinct_ecg_codes, 0)) AS sd_distinct_ecg_codes_per_patient
FROM (
  SELECT
    m.subject_id,
    IFNULL(pe.num_distinct_ecg_codes, 0) AS num_distinct_ecg_codes
  FROM male_81_91 m
  LEFT JOIN patient_ecg_counts pe
    ON m.subject_id = pe.subject_id
);