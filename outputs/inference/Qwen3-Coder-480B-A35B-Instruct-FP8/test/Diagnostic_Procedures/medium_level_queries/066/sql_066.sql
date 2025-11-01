WITH asthma_cohort AS (
  -- Identify patients with asthma diagnosis and filter by age and gender
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON p.subject_id = di.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.icd_code LIKE 'J45%'  -- ICD-10 codes for asthma
),

admissions_filtered AS (
  -- Get admissions for those patients and compute LOS
  SELECT
    a.hadm_id,
    a.subject_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN asthma_cohort ac ON a.subject_id = ac.subject_id
  WHERE DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

procedure_counts AS (
  -- Count diagnostic procedures per admission
  SELECT
    af.hadm_id,
    af.los_days,
    COUNT(*) AS proc_count
  FROM admissions_filtered af
  JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pr ON af.hadm_id = pr.hadm_id
  GROUP BY af.hadm_id, af.los_days
),

grouped_data AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    proc_count
  FROM procedure_counts
)

SELECT
  los_group,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(2)] AS percentile_50,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS percentile_75
FROM grouped_data
GROUP BY los_group
ORDER BY los_group;