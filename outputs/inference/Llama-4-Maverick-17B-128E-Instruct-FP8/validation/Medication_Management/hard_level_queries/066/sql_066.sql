WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'T%' OR icd_code LIKE 'Z94%'  -- Simplified transplant diagnosis filter
  )
),
med_complexity AS (
  SELECT c.hadm_id, COUNT(DISTINCT pr.drug) AS med_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.hadm_id
),
stratified AS (
  SELECT hadm_id, med_count,
         NTILE(4) OVER (ORDER BY med_count) AS quartile
  FROM med_complexity
),
outcomes AS (
  SELECT s.quartile,
         COUNT(*) AS n,
         AVG(s.med_count) AS mean_med_count,
         AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los,
         AVG(CASE WHEN c.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS in_hospital_mortality,
         AVG(CASE WHEN EXISTS (
           SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
           WHERE a2.subject_id = c.subject_id AND a2.admittime BETWEEN c.dischtime AND TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
         ) THEN 1 ELSE 0 END) AS readmission_30day
  FROM stratified s
  JOIN cohort c ON s.hadm_id = c.hadm_id
  GROUP BY s.quartile
)
SELECT * FROM outcomes
ORDER BY quartile;