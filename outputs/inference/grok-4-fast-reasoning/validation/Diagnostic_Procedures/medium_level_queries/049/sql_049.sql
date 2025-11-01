WITH qualifying_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 87 AND 97
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id 
        AND (LOWER(dd.long_title) LIKE '%sepsis%' OR LOWER(dd.long_title) LIKE '%septicemia%')
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id 
        AND LOWER(dd.long_title) LIKE '%septic shock%'
    )
)
SELECT 
  los_group,
  AVG(
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
     WHERE pi.hadm_id = qa.hadm_id
    ) 
  ) AS mean_num_diagnostic_procedures
FROM qualifying_admissions qa
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY MIN(los_days);