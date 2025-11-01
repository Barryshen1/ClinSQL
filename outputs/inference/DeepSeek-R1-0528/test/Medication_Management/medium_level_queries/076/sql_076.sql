WITH diabetes_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') OR
    (icd_version = 10 AND icd_code LIKE 'E1[0-4]%')
),
hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'acute.*heart failure|heart failure.*acute')
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 36
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN diabetes_codes dc 
        ON d.icd_code = dc.icd_code AND d.icd_version = dc.icd_version
      WHERE d.hadm_id = adm.hadm_id
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN hf_codes hc 
        ON d.icd_code = hc.icd_code AND d.icd_version = hc.icd_version
      WHERE d.hadm_id = adm.hadm_id
    )
),
glp1_orders AS (
  SELECT 
    hadm_id,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    (LOWER(drug) LIKE '%exenatide%' OR
     LOWER(drug) LIKE '%liraglutide%' OR
     LOWER(drug) LIKE '%dulaglutide%' OR
     LOWER(drug) LIKE '%semaglutide%' OR
     LOWER(drug) LIKE '%lixisenatide%') 
    AND (LOWER(route) LIKE '%subcut%' OR 
         LOWER(route) LIKE '%iv%' OR 
         LOWER(route) LIKE '%intraven%')
),
cohort_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
        WHEN g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) 
        THEN 1 ELSE 0 
    END) AS in_first_24h,
    MAX(CASE 
        WHEN g.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime 
        THEN 1 ELSE 0 
    END) AS in_final_12h
  FROM cohort c
  LEFT JOIN glp1_orders g 
    ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  ROUND(100.0 * SUM(in_first_24h) / COUNT(*), 2) AS pct_first_24h,
  ROUND(100.0 * SUM(in_final_12h) / COUNT(*), 2) AS pct_final_12h
FROM cohort_flags;