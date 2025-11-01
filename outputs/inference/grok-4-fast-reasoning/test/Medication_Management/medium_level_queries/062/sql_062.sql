WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
    HAVING 
      COUNTIF(
        (icd_version = 9 AND icd_code LIKE '250%') 
        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E(10|11|12|13|14)')))
      > 0
      AND 
      COUNTIF(
        (icd_version = 9 AND icd_code LIKE '428%') 
        OR (icd_version = 10 AND icd_code LIKE 'I50%'))
      > 0
  ) diag ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 50 AND 60
),
init AS (
  SELECT 
    c.*,
    (SELECT MIN(pr.starttime)
     FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
     WHERE pr.hadm_id = c.hadm_id
       AND pr.starttime >= c.admittime
       AND pr.starttime < c.dischtime
       AND (
         UPPER(pr.drug) LIKE '%LIRAGLUTIDE%' OR
         UPPER(pr.drug) LIKE '%EXENATIDE%' OR
         UPPER(pr.drug) LIKE '%DULAGLUTIDE%' OR
         UPPER(pr.drug) LIKE '%ALBIGLUTIDE%' OR
         UPPER(pr.drug) LIKE '%SEMAGLUTIDE%'
       )
       AND pr.route = 'SUBCUTANEOUS'
    ) AS first_start
  FROM cohort c
)
SELECT 
  COUNT(*) AS total_patients,
  SAFE_DIVIDE(
    COUNTIF(first_start IS NOT NULL AND first_start < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)), 
    COUNT(*)
  ) AS rate_first_72h,
  SAFE_DIVIDE(
    COUNTIF(first_start IS NOT NULL AND first_start >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AND first_start < dischtime), 
    COUNT(*)
  ) AS rate_final_72h,
  SAFE_DIVIDE(
    COUNTIF(first_start IS NOT NULL AND first_start >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AND first_start < dischtime), 
    COUNT(*)
  ) - SAFE_DIVIDE(
    COUNTIF(first_start IS NOT NULL AND first_start < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)), 
    COUNT(*)
  ) AS absolute_change,
  CASE 
    WHEN SAFE_DIVIDE(
      COUNTIF(first_start IS NOT NULL AND first_start < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)), 
      COUNT(*)
    ) > 0 
    THEN (
      SAFE_DIVIDE(
        COUNTIF(first_start IS NOT NULL AND first_start >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AND first_start < dischtime), 
        COUNT(*)
      ) - SAFE_DIVIDE(
        COUNTIF(first_start IS NOT NULL AND first_start < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)), 
        COUNT(*)
      )
    ) / SAFE_DIVIDE(
      COUNTIF(first_start IS NOT NULL AND first_start < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)), 
      COUNT(*)
    )
    ELSE NULL 
  END AS relative_change
FROM init;