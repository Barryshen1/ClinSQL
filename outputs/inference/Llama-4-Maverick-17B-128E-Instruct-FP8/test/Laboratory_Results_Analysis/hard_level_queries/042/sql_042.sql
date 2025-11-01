WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND d_diag.long_title LIKE '%Intracranial hemorrhage%'
),
labs AS (
  SELECT c.hadm_id, COUNT(DISTINCT l.itemid) AS abnormal_lab_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'  -- Using flag to determine abnormal labs
  GROUP BY c.hadm_id
),
instability_score_quartiles AS (
  SELECT hadm_id, abnormal_lab_count,
         NTILE(4) OVER (ORDER BY abnormal_lab_count) AS quartile
  FROM labs
),
outcomes AS (
  SELECT isq.quartile,
         COUNT(isq.hadm_id) AS count_patients,
         AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)) AS mean_los_hours,
         SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(isq.hadm_id) AS mortality_rate
  FROM instability_score_quartiles isq
  INNER JOIN cohort c ON isq.hadm_id = c.hadm_id
  GROUP BY isq.quartile
),
overall_mortality AS (
  SELECT AVG(hospital_expire_flag) AS overall_mortality_rate
  FROM cohort
)
SELECT o.*, om.overall_mortality_rate
FROM outcomes o
CROSS JOIN overall_mortality om
ORDER BY o.quartile;