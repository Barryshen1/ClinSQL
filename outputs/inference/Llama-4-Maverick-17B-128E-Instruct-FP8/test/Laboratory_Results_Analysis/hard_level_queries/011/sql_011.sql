WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 47 AND 57
),
admissions AS (
  SELECT hadm_id, subject_id, admittime, dischtime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
creatinine_labs AS (
  SELECT l.hadm_id, l.charttime, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label = 'Creatinine'
),
aki_patients AS (
  SELECT DISTINCT l.hadm_id
  FROM creatinine_labs l
  JOIN creatinine_labs l_prev ON l.hadm_id = l_prev.hadm_id AND l.charttime > l_prev.charttime
  WHERE l.valuenum >= 1.5 * l_prev.valuenum AND DATETIME_DIFF(l.charttime, l_prev.charttime, HOUR) <= 48
),
cohort AS (
  SELECT a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag,
         CASE WHEN a.hadm_id IN (SELECT hadm_id FROM aki_patients) THEN 1 ELSE 0 END AS has_aki
  FROM admissions a
  JOIN patients p ON a.subject_id = p.subject_id
),
lab_avg AS (
  SELECT hadm_id, AVG(valuenum) AS avg_valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
),
lab_instability AS (
  SELECT c.hadm_id, c.has_aki,
         AVG(ABS(l.valuenum - la.avg_valuenum)) AS lab_instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  JOIN lab_avg la ON c.hadm_id = la.hadm_id
  WHERE DATETIME_DIFF(l.charttime, c.admittime, HOUR) BETWEEN 0 AND 72
  GROUP BY c.hadm_id, c.has_aki
),
los AS (
  SELECT hadm_id, has_aki,
         DATETIME_DIFF(dischtime, admittime, HOUR) AS hospital_los
  FROM cohort
),
mortality AS (
  SELECT has_aki, AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort
  GROUP BY has_aki
)
SELECT 
  c.has_aki,
  AVG(li.lab_instability_score) AS mean_lab_instability_score,
  AVG(los.hospital_los) AS avg_hospital_los,
  m.mortality_rate
FROM cohort c
JOIN lab_instability li ON c.hadm_id = li.hadm_id
JOIN los ON c.hadm_id = los.hadm_id
JOIN mortality m ON c.has_aki = m.has_aki
GROUP BY c.has_aki, m.mortality_rate;