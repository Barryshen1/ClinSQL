WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
t2dm_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE 
    (d.icd_version = 9 AND d.icd_code LIKE '250%') 
    OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
),
hf_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE 
    (d.icd_version = 9 AND d.icd_code LIKE '428%') 
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),
glp1_administrations AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    ed.route,
    e.medication,
    ed.product_description
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  WHERE 
    (LOWER(e.medication) LIKE '%glp-1%' OR
     LOWER(e.medication) LIKE '%semaglutide%' OR
     LOWER(e.medication) LIKE '%liraglutide%' OR
     LOWER(e.medication) LIKE '%dulaglutide%' OR
     LOWER(e.medication) LIKE '%exenatide%' OR
     LOWER(e.medication) LIKE '%albiglutide%' OR
     LOWER(e.medication) LIKE '%lixisenatide%' OR
     LOWER(e.medication) LIKE '%tirzepatide%')
    OR
    (LOWER(ed.product_description) LIKE '%glp-1%' OR
     LOWER(ed.product_description) LIKE '%semaglutide%' OR
     LOWER(ed.product_description) LIKE '%liraglutide%' OR
     LOWER(ed.product_description) LIKE '%dulaglutide%' OR
     LOWER(ed.product_description) LIKE '%exenatide%' OR
     LOWER(ed.product_description) LIKE '%albiglutide%' OR
     LOWER(ed.product_description) LIKE '%lixisenatide%' OR
     LOWER(ed.product_description) LIKE '%tirzepatide%')
    AND ed.route IN ('subcutaneous', 'intramuscular', 'intravenous')
),
cohort_with_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MAX(CASE 
          WHEN ga.charttime >= c.admittime 
               AND ga.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS flag_first48,
    MAX(CASE 
          WHEN ga.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) 
               AND ga.charttime <= c.dischtime 
          THEN 1 ELSE 0 
        END) AS flag_final12
  FROM cohort c
  INNER JOIN t2dm_diagnoses t ON c.hadm_id = t.hadm_id
  INNER JOIN hf_diagnoses h ON c.hadm_id = h.hadm_id
  LEFT JOIN glp1_administrations ga 
    ON c.subject_id = ga.subject_id AND c.hadm_id = ga.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)
SELECT
  COUNT(*) AS total_admissions,
  ROUND(SUM(flag_first48) * 1.0 / COUNT(*), 4) AS prevalence_first48,
  ROUND(SUM(flag_final12) * 1.0 / COUNT(*), 4) AS prevalence_final12,
  ROUND((SUM(flag_first48) * 1.0 / COUNT(*)) - (SUM(flag_final12) * 1.0 / COUNT(*)), 4) AS absolute_difference
FROM cohort_with_flags;