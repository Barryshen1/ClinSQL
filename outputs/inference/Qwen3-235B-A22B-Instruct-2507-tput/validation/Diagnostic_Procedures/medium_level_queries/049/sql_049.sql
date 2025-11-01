WITH sepsis_patients AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 87 AND p.anchor_age <= 97
    AND d.icd_code LIKE 'A40%' 
    AND di.icd_version = 10
    AND a.hadm_id NOT IN (
      SELECT di2.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2 ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
      WHERE d2.icd_code = 'R65.21' AND di2.icd_version = 10
    )
),
admission_duration AS (
  SELECT 
    sp.hadm_id,
    DATETIME_DIFF(sp.dischtime, sp.admittime, DAY) AS los_days
  FROM sepsis_patients sp
  WHERE DATETIME_DIFF(sp.dischtime, sp.admittime, DAY) BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT 
    ad.hadm_id,
    ad.los_days,
    COUNT(pi.icd_code) AS procedure_count
  FROM admission_duration ad
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON ad.hadm_id = pi.hadm_id
  GROUP BY ad.hadm_id, ad.los_days
),
los_groups AS (
  SELECT 
    hadm_id,
    procedure_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM procedure_counts
)
SELECT 
  los_group,
  AVG(procedure_count) AS mean_diagnostic_procedures
FROM los_groups
GROUP BY los_group
ORDER BY los_group;