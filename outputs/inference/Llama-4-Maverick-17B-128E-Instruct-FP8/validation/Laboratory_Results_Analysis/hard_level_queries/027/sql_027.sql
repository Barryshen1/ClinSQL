WITH 
cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 89 AND 99
  AND dicd.long_title LIKE '%Gastrointestinal hemorrhage%'  
),

lab_events AS (
  SELECT c.hadm_id, 
         SUM(CASE 
             WHEN (dl.ref_range_lower IS NOT NULL AND dl.ref_range_upper IS NOT NULL) 
                  AND (l.valuenum < dl.ref_range_lower OR l.valuenum > dl.ref_range_upper) 
             THEN 1 ELSE 0 END) AS lab_instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE DATETIME_DIFF(l.charttime, c.admittime, HOUR) <= 72
  GROUP BY c.hadm_id
),

quintiles AS (
  SELECT hadm_id, lab_instability_score,
         NTILE(5) OVER (ORDER BY lab_instability_score) AS quintile
  FROM lab_events
),

results AS (
  SELECT q.quintile,
         AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los,
         SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate,
         AVG(q.lab_instability_score) AS avg_lab_instability_score
  FROM quintiles q
  INNER JOIN cohort c ON q.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  GROUP BY q.quintile
)

SELECT * FROM results
ORDER BY quintile;