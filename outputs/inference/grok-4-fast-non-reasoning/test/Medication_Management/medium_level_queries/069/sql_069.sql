WITH cohort AS (
  -- Base cohort: males 48-58 with admissions
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (a.deathtime IS NULL OR a.deathtime > a.admittime)
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths for final 12h relevance
    AND (a.dischtime - a.admittime) >= INTERVAL 12 HOUR  -- Ensure LOS >=12h for meaningful windows
),
t2dm_patients AS (
  -- Patients with T2DM (ICD-10 E11%)
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'E11%'
),
hf_patients AS (
  -- Patients with heart failure (ICD-10 I50%)
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'I50%'
),
qualified_admissions AS (
  -- First admission per patient in cohort with both conditions
  SELECT 
    c.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY a.admittime) AS rn
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
  INNER JOIN t2dm_patients t2
    ON c.subject_id = t2.subject_id
  INNER JOIN hf_patients h
    ON c.subject_id = h.subject_id
  WHERE (a.dischtime - a.admittime) >= INTERVAL 12 HOUR
),
glp1_flags AS (
  -- Flag GLP-1 prescriptions in time windows (first admission only)
  SELECT 
    qa.subject_id,
    MAX(CASE 
      WHEN pr.starttime >= qa.admittime 
        AND pr.starttime <= TIMESTAMP_ADD(qa.admittime, INTERVAL 12 HOUR)
        AND (pr.drug LIKE '%semaglutide%' OR pr.drug LIKE '%liraglutide%' 
        OR pr.drug LIKE '%dulaglutide%' OR pr.drug LIKE '%exenatide%' 
        OR pr.drug LIKE '%albiglutide%' OR pr.drug LIKE '%lixisenatide%')
      THEN 1 ELSE 0 
    END) AS has_first12,
    MAX(CASE 
      WHEN pr.starttime >= TIMESTAMP_SUB(qa.dischtime, INTERVAL 12 HOUR)
        AND pr.starttime < qa.dischtime
        AND (pr.drug LIKE '%semaglutide%' OR pr.drug LIKE '%liraglutide%' 
        OR pr.drug LIKE '%dulaglutide%' OR pr.drug LIKE '%exenatide%' 
        OR pr.drug LIKE '%albiglutide%' OR pr.drug LIKE '%lixisenatide%')
      THEN 1 ELSE 0 
    END) AS has_final12
  FROM qualified_admissions qa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON qa.subject_id = pr.subject_id 
    AND qa.hadm_id = pr.hadm_id
    AND pr.starttime IS NOT NULL
  WHERE qa.rn = 1  -- First admission only
  GROUP BY qa.subject_id
)
-- Aggregations
SELECT 
  COUNT(*) AS total_patients,
  SUM(has_first12) AS num_first12,
  ROUND(SUM(has_first12) * 100.0 / COUNT(*), 2) AS first12_pct,
  SUM(has_final12) AS num_final12,
  ROUND(SUM(has_final12) * 100.0 / COUNT(*), 2) AS final12_pct,
  ROUND(SUM(has_first12) * 100.0 / COUNT(*) - SUM(has_final12) * 100.0 / COUNT(*), 2) AS net_change_pct
FROM glp1_flags;