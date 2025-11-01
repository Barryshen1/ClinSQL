WITH 
cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 80 AND 90
  AND d.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE lower(long_title) LIKE '%hepatic failure%')
),
med_complexity AS (
  SELECT c.hadm_id, COUNT(DISTINCT p.drug) AS med_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),
tertiles AS (
  SELECT hadm_id, med_count, NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM med_complexity
),
outcomes AS (
  SELECT 
    t.tertile,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los_hours,
    SUM(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality,
    SUM(CASE WHEN next_admit.admittime BETWEEN a.dischtime AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) / COUNT(*) AS readmission_rate
  FROM tertiles t
  INNER JOIN cohort c ON t.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_admit ON c.subject_id = next_admit.subject_id AND next_admit.admittime > a.dischtime
  GROUP BY t.tertile
)
SELECT * FROM outcomes;