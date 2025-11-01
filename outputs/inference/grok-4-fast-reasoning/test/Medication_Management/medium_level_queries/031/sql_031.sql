WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.icd_version = 10
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING COUNTIF(d.icd_code LIKE 'E10%' 
         OR d.icd_code LIKE 'E11%' 
         OR d.icd_code LIKE 'E12%' 
         OR d.icd_code LIKE 'E13%' 
         OR d.icd_code LIKE 'E14%') > 0
     AND COUNTIF(d.icd_code LIKE 'I50%') > 0
),
glp_initiations AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    MIN(pr.starttime) AS init_time
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime 
    AND pr.starttime <= c.dischtime
    AND pr.route = 'Subcutaneous'
    AND (LOWER(pr.drug) LIKE '%liraglutide%' 
         OR LOWER(pr.drug) LIKE '%exenatide%' 
         OR LOWER(pr.drug) LIKE '%dulaglutide%' 
         OR LOWER(pr.drug) LIKE '%semaglutide%' 
         OR LOWER(pr.drug) LIKE '%lixisenatide%' 
         OR LOWER(pr.drug) LIKE '%albiglutide%')
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  COUNT(DISTINCT c.hadm_id) AS total_cohort,
  ROUND(
    COUNT(DISTINCT CASE 
      WHEN g.init_time >= c.admittime 
           AND g.init_time < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) 
      THEN c.hadm_id 
    END) * 100.0 / COUNT(DISTINCT c.hadm_id), 
    2
  ) AS pct_initiated_first_24h,
  ROUND(
    COUNT(DISTINCT CASE 
      WHEN g.init_time >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) 
           AND g.init_time < c.dischtime 
      THEN c.hadm_id 
    END) * 100.0 / COUNT(DISTINCT c.hadm_id), 
    2
  ) AS pct_initiated_last_12h
FROM cohort c
LEFT JOIN glp_initiations g 
  ON c.hadm_id = g.hadm_id;