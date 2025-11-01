WITH qualifying_admissions AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.subject_id = diag.subject_id 
    AND a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON diag.icd_code = icd.icd_code 
    AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 76
    AND (LOWER(icd.long_title) LIKE '%sepsis%' OR LOWER(icd.long_title) LIKE '%septic%')
),
platelet_avgs AS (
  SELECT 
    qa.subject_id,
    qa.hadm_id,
    AVG(l.valuenum) AS avg_platelet_first24
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON qa.subject_id = l.subject_id 
    AND qa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON l.itemid = li.itemid
  WHERE l.charttime >= qa.admittime 
    AND l.charttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 1 DAY)
    AND LOWER(li.label) LIKE '%platelet%'
    AND l.valuenum IS NOT NULL
  GROUP BY qa.subject_id, qa.hadm_id
)
SELECT 
  AVG(avg_platelet_first24) AS median_avg_platelet
FROM (
  SELECT 
    avg_platelet_first24,
    ROW_NUMBER() OVER (ORDER BY avg_platelet_first24) AS rn,
    COUNT(*) OVER () AS cnt
  FROM platelet_avgs
) t
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2));