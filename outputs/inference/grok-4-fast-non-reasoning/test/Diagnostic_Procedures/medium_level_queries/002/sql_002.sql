WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    d.icd_code AS tia_icd,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.subject_id = a.subject_id 
          AND i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
    AND d.icd_version IN (9, 10)
    AND (
      (d.icd_version = 10 AND d.icd_code = 'G45.9') OR
      (d.icd_version = 9 AND d.icd_code = '435.9')
    )
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.hospital_expire_flag = 0
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 7
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
)

SELECT 
  c.los_group,
  c.icu_flag,
  AVG(COALESCE(proc_count, 0)) AS mean_procedures_per_admission,
  COUNT(*) AS num_admissions
FROM 
  cohort c
LEFT JOIN (
  SELECT 
    pr.hadm_id,
    COUNT(*) AS proc_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  WHERE 
    pr.icd_version IN (9, 10)
    AND (
      -- ICD-10: Ultrasounds and Echocardiograms
      pr.icd_code LIKE 'BW%' OR pr.icd_code LIKE 'B24%' OR
      -- ICD-9: Ultrasounds and Echocardiograms
      pr.icd_code LIKE '88%' OR pr.icd_code LIKE '37.2%'
    )
  GROUP BY 
    pr.hadm_id
) proc
ON c.hadm_id = proc.hadm_id
WHERE 
  c.los_group IS NOT NULL
GROUP BY 
  c.los_group, 
  c.icu_flag
ORDER BY 
  los_group, icu_flag;