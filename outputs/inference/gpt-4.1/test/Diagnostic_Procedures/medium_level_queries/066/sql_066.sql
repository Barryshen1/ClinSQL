WITH asthma_patients AS (
  -- Identify female patients aged 88–98
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
asthma_admissions AS (
  -- Admissions with asthma diagnosis
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN asthma_patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^493'))
    OR
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J45'))
  )
),
admission_los AS (
  -- Calculate LOS and filter for 1–3 and 4–7 day stays
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM asthma_admissions
  WHERE DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),
diagnostic_procedure_counts AS (
  -- Count diagnostic procedures per admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_group,
    COUNT(p.icd_code) AS diagnostic_procedure_count
  FROM admission_los a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON a.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE a.los_group IS NOT NULL
    AND (
      dp.long_title IS NOT NULL
      AND LOWER(dp.long_title) LIKE '%diagnostic%'
    )
  GROUP BY a.subject_id, a.hadm_id, a.los_group
),
all_admissions_with_counts AS (
  -- Include admissions with zero diagnostic procedures
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_group,
    COALESCE(d.diagnostic_procedure_count, 0) AS diagnostic_procedure_count
  FROM admission_los a
  LEFT JOIN diagnostic_procedure_counts d
    ON a.hadm_id = d.hadm_id
  WHERE a.los_group IS NOT NULL
)
SELECT
  los_group,
  APPROX_QUANTILES(diagnostic_procedure_count, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(diagnostic_procedure_count, 4)[OFFSET(2)] AS percentile_50,
  APPROX_QUANTILES(diagnostic_procedure_count, 4)[OFFSET(3)] AS percentile_75
FROM all_admissions_with_counts
GROUP BY los_group
ORDER BY los_group;