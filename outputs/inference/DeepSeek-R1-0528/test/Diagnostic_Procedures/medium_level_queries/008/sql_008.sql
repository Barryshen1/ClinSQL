WITH base_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code IN ('250.20','250.21','250.22','250.23','250.29'))
          OR 
          (di.icd_version = 10 AND di.icd_code IN ('E11.00','E11.01','E13.00','E13.01','E10.10','E10.11','E13.10','E13.11'))
        )
    )
),

admissions_with_los AS (
  SELECT 
    subject_id, 
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM base_admissions
  WHERE 
    age_at_admission BETWEEN 58 AND 68
    AND DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),

proc_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_rad_ct
  FROM (
    SELECT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE 
      LOWER(d.long_title) LIKE '%radiography%'
      OR LOWER(d.long_title) LIKE '%ct%'
      OR LOWER(d.long_title) LIKE '%computed tomography%'

    UNION ALL

    SELECT h.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
      ON h.hcpcs_cd = d.code
    WHERE 
      LOWER(d.short_description) LIKE '%radiography%'
      OR LOWER(d.short_description) LIKE '%ct%'
      OR LOWER(d.short_description) LIKE '%computed tomography%'
  ) combined
  GROUP BY hadm_id
)

SELECT 
  a.los_group,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(COALESCE(p.num_rad_ct, 0)) AS mean_rad_ct_per_admission
FROM admissions_with_los a
LEFT JOIN proc_counts p 
  ON a.hadm_id = p.hadm_id
WHERE a.los_group IS NOT NULL
GROUP BY a.los_group;