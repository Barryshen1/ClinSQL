WITH patient_adms AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender, 
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) <= 4 THEN '1-4' 
      ELSE '5-7' 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),
primary_acs AS (
  SELECT DISTINCT d.hadm_id
  FROM patient_adms pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON pa.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%'))
      OR 
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'))
    )
),
secondary_acs AS (
  SELECT DISTINCT d.hadm_id
  FROM patient_adms pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON pa.hadm_id = d.hadm_id
  WHERE d.seq_num > 1
    AND (
      (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%'))
      OR 
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'))
    )
    AND d.hadm_id NOT IN (SELECT hadm_id FROM primary_acs)
),
filtered_adms AS (
  SELECT pa.*, 'primary' AS acs_type
  FROM patient_adms pa
  INNER JOIN primary_acs pr ON pa.hadm_id = pr.hadm_id
  
  UNION ALL
  
  SELECT pa.*, 'secondary' AS acs_type
  FROM patient_adms pa
  INNER JOIN secondary_acs sec ON pa.hadm_id = sec.hadm_id
),
ultrasound_counts AS (
  SELECT 
    f.hadm_id, 
    f.los_group, 
    f.acs_type,
    COALESCE(uc.num_procs, 0) AS num_ultrasounds
  FROM filtered_adms f
  LEFT JOIN (
    SELECT 
      p.hadm_id,
      COUNT(*) AS num_procs
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
      ON p.icd_code = dip.icd_code 
      AND p.icd_version = dip.icd_version
    WHERE dip.long_title LIKE '%echocardiography%' 
       OR dip.long_title LIKE '%ultrasonography%'
    GROUP BY p.hadm_id
  ) uc ON f.hadm_id = uc.hadm_id
)
SELECT 
  los_group, 
  acs_type,
  APPROX_QUANTILES(num_ultrasounds, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_ultrasounds, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_ultrasounds, 4)[OFFSET(3)] AS p75
FROM ultrasound_counts
GROUP BY los_group, acs_type
ORDER BY los_group, acs_type;