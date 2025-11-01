WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE 'Other' 
    END AS los_group,
    diag.seq_num,
    CASE 
      WHEN diag.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary' 
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND diag.icd_version = 10
    AND (d.icd_code LIKE 'I21%' 
         OR d.icd_code LIKE 'I22%' 
         OR d.icd_code LIKE 'I23%' 
         OR d.icd_code LIKE 'I24%')
),

ultrasound_counts AS (
  SELECT 
    aa.hadm_id,
    aa.los_group,
    aa.diagnosis_type,
    COUNT(DISTINCT proc.icd_code) AS num_ultrasounds
  FROM acs_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON aa.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
  WHERE 
    (dip.icd_code LIKE 'B%' 
     OR LOWER(dip.long_title) LIKE '%ultrasound%' 
     OR LOWER(dip.long_title) LIKE '%echocardiogram%')
  GROUP BY aa.hadm_id, aa.los_group, aa.diagnosis_type
)

SELECT 
  los_group,
  diagnosis_type,
  AVG(num_ultrasounds) AS mean_ultrasounds,
  MIN(num_ultrasounds) AS min_ultrasounds,
  MAX(num_ultrasounds) AS max_ultrasounds,
  COUNT(*) AS num_admissions
FROM ultrasound_counts
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;