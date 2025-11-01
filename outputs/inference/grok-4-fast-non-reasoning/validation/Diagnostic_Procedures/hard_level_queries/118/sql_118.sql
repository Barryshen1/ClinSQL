WITH first_icu_stays AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id, icu.hadm_id ORDER BY icu.intime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON icu.hadm_id = adm.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 44 AND 54
),
ami_cohort AS (
  SELECT 
    fis.*,
    diag.icd_code,
    diag.icd_version
  FROM 
    first_icu_stays fis
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON fis.hadm_id = diag.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code 
    AND diag.icd_version = d_icd.icd_version
  WHERE 
    fis.rn = 1
    AND (
      (diag.icd_version = '9' AND STARTS_WITH(diag.icd_code, '410'))
      OR (diag.icd_version = '10' AND diag.icd_code = 'I21')
    )
    AND diag.seq_num = 1  -- Primary diagnosis
),
procedure_counts AS (
  SELECT 
    ac.*,
    COUNT(DISTINCT proc.itemid) AS procedure_count
  FROM 
    ami_cohort ac
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` proc
  ON ac.subject_id = proc.subject_id
    AND ac.hadm_id = proc.hadm_id
    AND ac.stay_id = proc.stay_id
    AND proc.starttime IS NOT NULL
    AND proc.starttime <= TIMESTAMP_ADD(ac.intime, INTERVAL 72 HOUR)
  GROUP BY 
    ac.subject_id, ac.hadm_id, ac.stay_id, ac.intime, ac.admittime, ac.dischtime, ac.hospital_expire_flag, ac.anchor_age
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM 
    procedure_counts
)
SELECT 
  CASE 
    WHEN quartile = 1 THEN 'Q1 (Lowest)'
    WHEN quartile = 2 THEN 'Q2'
    WHEN quartile = 3 THEN 'Q3'
    ELSE 'Q4 (Highest)'
  END AS quartile_str,
  COUNT(*) AS n,
  ROUND(AVG(CAST(procedure_count AS FLOAT64)), 2) AS mean_procedure_count,
  ROUND(AVG(
    EXTRACT(DAY FROM dischtime - admittime) + 
    EXTRACT(HOUR FROM dischtime - admittime) / 24.0
  ), 2) AS mean_hospital_los_days,
  ROUND(
    (SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*)), 
    2
  ) AS in_hospital_mortality_percent
FROM 
  quartiles
GROUP BY 
  quartile
ORDER BY 
  quartile;