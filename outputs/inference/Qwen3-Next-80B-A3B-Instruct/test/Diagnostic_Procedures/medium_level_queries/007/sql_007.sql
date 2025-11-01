WITH acs_admissions AS (
  SELECT
    d.hadm_id,
    CASE WHEN d.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS acs_diagnosis_type
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(di.long_title) LIKE '%myocardial infarction%'
     OR LOWER(di.long_title) LIKE '%unstable angina%'
),

procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_procedures
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd
  GROUP BY hadm_id
),

filtered_admissions AS (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    acs.acs_diagnosis_type,
    COALESCE(pc.num_procedures, 0) AS num_procedures
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN acs_admissions acs ON a.hadm_id = acs.hadm_id
  LEFT JOIN procedure_counts pc ON a.hadm_id = pc.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
)

SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  acs_diagnosis_type,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(3)] AS p75
FROM filtered_admissions
GROUP BY los_group, acs_diagnosis_type
ORDER BY los_group, acs_diagnosis_type;