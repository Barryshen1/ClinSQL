WITH 
cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN cohort c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
),
med_complexity AS (
  SELECT i.stay_id, COUNT(DISTINCT p.drug) AS num_medications
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON i.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id
),
quintiles AS (
  SELECT stay_id, num_medications,
         NTILE(5) OVER (ORDER BY num_medications) AS quintile
  FROM med_complexity
),
outcomes AS (
  SELECT 
    q.quintile,
    AVG(TIMESTAMP_DIFF(i.outtime, i.intime, HOUR)) AS avg_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT i.stay_id) AS in_hospital_mortality,
    SUM(CASE WHEN c.next_admit_time <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) / COUNT(DISTINCT i.stay_id) AS readmission_30day
  FROM quintiles q
  JOIN icu_stays i ON q.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT subject_id, hadm_id, dischtime, 
           LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admit_time
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  GROUP BY q.quintile
)
SELECT * FROM outcomes;