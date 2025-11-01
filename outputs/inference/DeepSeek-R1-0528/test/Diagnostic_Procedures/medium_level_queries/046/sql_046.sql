WITH tia_admissions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%transient ischemic attack%'
),

base AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN tia_admissions tia 
    ON adm.hadm_id = tia.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),

base_with_los AS (
  SELECT 
    subject_id,
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
        WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
        WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
        ELSE 'Other'
    END AS los_group
  FROM base
),

procedures AS (
  SELECT hadm_id, COUNT(*) AS proc_count
  FROM (
    SELECT proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON proc.icd_code = d.icd_code AND proc.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%ct%' OR LOWER(d.long_title) LIKE '%mri%'

    UNION ALL

    SELECT hcpc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
      ON hcpc.hcpcs_cd = d.code
    WHERE LOWER(d.long_description) LIKE '%ct%' OR LOWER(d.long_description) LIKE '%mri%'
  ) 
  GROUP BY hadm_id
)

SELECT 
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(COALESCE(proc_count, 0)) AS mean_procedures_per_admission
FROM base_with_los b
LEFT JOIN procedures p 
  ON b.hadm_id = p.hadm_id
WHERE los_group IN ('1-3', '4-7')
GROUP BY los_group;