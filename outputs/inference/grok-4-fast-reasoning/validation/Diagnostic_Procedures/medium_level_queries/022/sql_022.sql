WITH cohort AS (
  SELECT 
    hadm_id,
    admission_type,
    CASE 
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) <= 4 THEN '1-4 days' 
      ELSE '5-7 days' 
    END AS stay_group,
    CASE 
      WHEN admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent' 
      ELSE 'Elective' 
    END AS adm_group
  FROM (
    SELECT 
      a.hadm_id,
      a.admission_type,
      a.admittime,
      a.dischtime,
      p.gender,
      p.anchor_age,
      DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age = 74
      AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
      AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
      AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
          ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE 
          di.subject_id = a.subject_id 
          AND di.hadm_id = a.hadm_id
          AND LOWER(dd.long_title) LIKE '%heart failure%'
      )
  )
),
proc_counts AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS num_diags
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
      ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE 
    pi.hadm_id IN (SELECT hadm_id FROM cohort)
    AND (
      LOWER(dp.long_title) LIKE '%x-ray%' OR
      LOWER(dp.long_title) LIKE '%radiograph%' OR
      LOWER(dp.long_title) LIKE '%tomography%' OR
      LOWER(dp.long_title) LIKE '%magnetic resonance%' OR
      LOWER(dp.long_title) LIKE '%ultrasound%' OR
      LOWER(dp.long_title) LIKE '%echocardiography%' OR
      LOWER(dp.long_title) LIKE '%electrocardiogram%' OR
      LOWER(dp.long_title) LIKE '%ecg%' OR
      LOWER(dp.long_title) LIKE '%ekg%' OR
      LOWER(dp.long_title) LIKE '%electroencephalogram%' OR
      LOWER(dp.long_title) LIKE '%eeg%' OR
      LOWER(dp.long_title) LIKE '%pulmonary function%' OR
      LOWER(dp.long_title) LIKE '%spirometry%'
    )
  GROUP BY 
    pi.hadm_id
)
SELECT 
  c.stay_group,
  c.adm_group,
  AVG(COALESCE(pc.num_diags, 0)) AS mean_noninvasive_diags_per_admission
FROM 
  cohort c
LEFT JOIN 
  proc_counts pc ON c.hadm_id = pc.hadm_id
GROUP BY 
  c.stay_group, 
  c.adm_group
ORDER BY 
  stay_group, 
  adm_group;