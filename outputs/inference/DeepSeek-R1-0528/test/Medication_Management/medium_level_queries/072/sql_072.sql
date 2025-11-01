WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 79 AND 89
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[0-9]{2}$') AND CAST(SUBSTR(icd_code, 5, 1) AS INT) IN (0, 2))
        OR 
        (icd_version = 10 AND icd_code LIKE 'E11%')
    )
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%')
        OR 
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
    AND adm.dischtime > DATETIME_ADD(adm.admittime, INTERVAL 12 HOUR)  -- Ensure valid time windows
),

cohort_with_flags AS (
  SELECT 
    c.hadm_id,
    -- Flag for GLP-1 in first 12h
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE 
        e.hadm_id = c.hadm_id
        AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
        AND REGEXP_CONTAINS(LOWER(e.medication), r'exenatide|liraglutide|dulaglutide|lixisenatide|semaglutide|albiglutide')
    ) THEN 1 ELSE 0 END AS flag_first_12h,
    -- Flag for GLP-1 in final 24h
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE 
        e.hadm_id = c.hadm_id
        AND e.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
        AND REGEXP_CONTAINS(LOWER(e.medication), r'exenatide|liraglutide|dulaglutide|lixisenatide|semaglutide|albiglutide')
    ) THEN 1 ELSE 0 END AS flag_last_24h
  FROM cohort c
)

SELECT 
  COUNT(*) AS total_admissions,
  SUM(flag_first_12h) AS count_first_12h,
  SUM(flag_last_24h) AS count_last_24h,
  ROUND(SUM(flag_first_12h) * 100.0 / COUNT(*), 2) AS percent_first_12h,
  ROUND(SUM(flag_last_24h) * 100.0 / COUNT(*), 2) AS percent_last_24h,
  ROUND(
    (SUM(flag_last_24h) * 100.0 / COUNT(*)) - (SUM(flag_first_12h) * 100.0 / COUNT(*)), 
    2
  ) AS net_change_percentage_points
FROM cohort_with_flags;