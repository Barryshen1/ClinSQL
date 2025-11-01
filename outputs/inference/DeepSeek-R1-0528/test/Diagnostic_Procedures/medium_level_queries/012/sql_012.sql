WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '411%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')
          OR (diag.icd_version = 10 AND diag.icd_code = 'I20.0')
        )
    )
),
los_groups AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM acs_admissions
  WHERE los_days BETWEEN 1 AND 7
),
ultrasound_counts AS (
  SELECT 
    proc.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code 
    AND proc.icd_version = dicd.icd_version
  WHERE 
    LOWER(dicd.long_title) LIKE '%ultrasound%' 
    OR LOWER(dicd.long_title) LIKE '%echocardiography%'
  GROUP BY proc.hadm_id
)
SELECT 
  g.los_group,
  COUNT(DISTINCT g.hadm_id) AS patient_count,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds
FROM los_groups g
LEFT JOIN ultrasound_counts u
  ON g.hadm_id = u.hadm_id
GROUP BY g.los_group
ORDER BY g.los_group;