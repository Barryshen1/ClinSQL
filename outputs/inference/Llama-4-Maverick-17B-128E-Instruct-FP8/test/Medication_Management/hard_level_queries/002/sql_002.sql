WITH ami_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 67 AND 77
  AND d.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Acute myocardial infarction%')
),
med_complexity AS (
  SELECT a.subject_id, a.hadm_id, COUNT(DISTINCT pr.drug) as med_count
  FROM ami_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.hadm_id = pr.hadm_id
  WHERE pr.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),
tertiles AS (
  SELECT hadm_id, med_count,
  NTILE(3) OVER (ORDER BY med_count) as tertile
  FROM med_complexity
),
stats AS (
  SELECT t.tertile,
  COUNT(t.hadm_id) as admission_count,
  MIN(m.med_count) as score_min, MAX(m.med_count) as score_max, AVG(m.med_count) as score_mean,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) as los_mean,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(t.hadm_id) * 100 as mortality_percent,
  SUM(CASE WHEN EXISTS (
    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
    WHERE a2.subject_id = a.subject_id AND a2.admittime > a.dischtime AND TIMESTAMP_DIFF(a2.admittime, a.dischtime, DAY) <= 30
  ) THEN 1 ELSE 0 END) / COUNT(t.hadm_id) * 100 as readmission_percent
  FROM tertiles t
  JOIN med_complexity m ON t.hadm_id = m.hadm_id
  JOIN ami_patients a ON t.hadm_id = a.hadm_id
  GROUP BY t.tertile
)
SELECT * FROM stats
ORDER BY tertile;