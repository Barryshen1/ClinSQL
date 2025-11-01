WITH eligible AS (
  -- Admissions that are female, age 47-57 at admission, with acute pancreatitis
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag
    ON di.icd_code = diag.icd_code AND di.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%pancreatitis%'
    AND a.dischtime IS NOT NULL
    AND LOWER(p.gender) = 'f'
),
eligible_with_los AS (
  SELECT
    e.*,
    CAST(FLOOR(TIMESTAMP_DIFF(e.dischtime, e.admittime, SECOND) / 86400.0) AS INT64) AS los_days
  FROM eligible e
),
eligible_group AS (
  SELECT
    e.*,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group
  FROM eligible_with_los e
  WHERE los_days BETWEEN 1 AND 8
),
ct_mri_per_adm AS (
  -- CT/MRI related procedures per admission
  SELECT hadm_id, COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
    ON proc.icd_code = di.icd_code AND proc.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%ct%'
     OR LOWER(di.long_title) LIKE '%mri%'
  GROUP BY hadm_id
)
SELECT
  g.los_group,
  COUNT(DISTINCT g.subject_id) AS patient_count,
  AVG(COALESCE(c.ct_mri_count, 0)) AS mean_ct_mri_per_admission
FROM eligible_group AS g
LEFT JOIN ct_mri_per_adm AS c
  ON g.hadm_id = c.hadm_id
WHERE g.los_group IS NOT NULL
GROUP BY g.los_group
ORDER BY g.los_group;