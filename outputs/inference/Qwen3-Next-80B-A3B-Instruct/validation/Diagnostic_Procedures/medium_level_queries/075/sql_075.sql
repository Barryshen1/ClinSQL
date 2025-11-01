WITH acs_admissions AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_acs,
    MAX(CASE WHEN di.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary_acs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%acute coronary syndrome%'
     OR LOWER(ddi.long_title) LIKE '%myocardial infarction%'
     OR LOWER(ddi.long_title) LIKE '%unstable angina%'
  GROUP BY di.hadm_id
  HAVING has_primary_acs = 1 OR has_secondary_acs = 1
),

icu_los_per_admission AS (
  SELECT hadm_id, SUM(los) AS total_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

procedure_counts AS (
  SELECT hadm_id, COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),

eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 59 AND 69
),

admissions_with_acs_and_eligible AS (
  SELECT 
    aa.hadm_id,
    CASE 
      WHEN aa.has_primary_acs = 1 THEN 'primary'
      WHEN aa.has_secondary_acs = 1 THEN 'secondary'
    END AS diag_type
  FROM acs_admissions aa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON aa.hadm_id = a.hadm_id
  JOIN eligible_patients ep
    ON a.subject_id = ep.subject_id
),

final_data AS (
  SELECT 
    CASE 
      WHEN il.total_los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN il.total_los BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    awa.diag_type,
    pc.procedure_count
  FROM admissions_with_acs_and_eligible awa
  JOIN icu_los_per_admission il ON awa.hadm_id = il.hadm_id
  JOIN procedure_counts pc ON awa.hadm_id = pc.hadm_id
  WHERE il.total_los BETWEEN 1 AND 7
)

SELECT 
  los_group,
  diag_type,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS p75
FROM final_data
WHERE los_group IS NOT NULL AND diag_type IS NOT NULL
GROUP BY los_group, diag_type
ORDER BY los_group, diag_type;