WITH tia_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE 
    (d.icd_version = 9 AND d.icd_code LIKE '435%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'G45.%')
),
base AS (
  SELECT 
    a.hadm_id,
    ANY_VALUE(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS hospital_los,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN tia_admissions t 
    ON a.hadm_id = t.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 64 AND 74
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  GROUP BY a.hadm_id
),
echocount AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS echo_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%echocardiogram%'
  GROUP BY p.hadm_id
)
SELECT 
  CASE 
    WHEN b.hospital_los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN b.hospital_los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  CASE 
    WHEN b.icu_flag = 1 THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_group,
  AVG(COALESCE(e.echo_count, 0)) AS mean_echo_per_admission,
  COUNT(*) AS num_admissions
FROM base b
LEFT JOIN echocount e
  ON b.hadm_id = e.hadm_id
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;