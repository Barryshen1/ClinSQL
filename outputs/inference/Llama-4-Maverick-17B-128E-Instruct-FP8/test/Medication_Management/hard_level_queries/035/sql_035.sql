WITH 
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
),
neutropenic_fever AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE dli.label IN ('Neutrophils', 'Temperature') AND (le.valuenum < 1.0 OR le.valuenum > 38.0)
),
med_complexity AS (
  SELECT a.hadm_id, COUNT(DISTINCT p.drug) AS med_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON a.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id
),
combined_data AS (
  SELECT ep.subject_id, ep.hadm_id, ep.admittime, ep.dischtime, mc.med_count,
         TIMESTAMP_DIFF(ep.dischtime, ep.admittime, HOUR) AS los,
         CASE WHEN ep.dischtime IS NOT NULL AND a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS hospital_expire_flag,
         LAG(ep.admittime) OVER (PARTITION BY ep.subject_id ORDER BY ep.admittime) AS prev_admittime
  FROM eligible_patients ep
  JOIN neutropenic_fever nf ON ep.hadm_id = nf.hadm_id
  JOIN med_complexity mc ON ep.hadm_id = mc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ep.hadm_id = a.hadm_id
),
quartiles AS (
  SELECT hadm_id, med_count, NTILE(4) OVER (ORDER BY med_count) AS quartile
  FROM combined_data
),
final_stats AS (
  SELECT q.quartile,
         COUNT(*) AS patient_count,
         AVG(c.med_count) AS mean_med_count,
         MIN(c.med_count) AS min_med_count,
         MAX(c.med_count) AS max_med_count,
         AVG(c.los) AS mean_los,
         SUM(c.hospital_expire_flag) / COUNT(*) * 100 AS mortality_percent,
         SUM(CASE WHEN c.prev_admittime IS NOT NULL AND TIMESTAMP_DIFF(c.admittime, c.prev_admittime, DAY) <= 30 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS readmission_percent
  FROM quartiles q
  JOIN combined_data c ON q.hadm_id = c.hadm_id
  GROUP BY q.quartile
)
SELECT * FROM final_stats
ORDER BY quartile;