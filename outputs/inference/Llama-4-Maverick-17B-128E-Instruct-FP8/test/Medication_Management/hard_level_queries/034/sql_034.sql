WITH 
surgical_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 51 AND 61
  AND a.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`)
),
med_complexity AS (
  SELECT hadm_id, 
         COUNT(DISTINCT drug) AS unique_drugs,
         COUNT(DISTINCT drug) + COUNT(DISTINCT pharmacy_id) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM surgical_admissions)
  AND starttime BETWEEN (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE hadm_id IN (SELECT hadm_id FROM surgical_admissions)) 
  AND (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE hadm_id IN (SELECT hadm_id FROM surgical_admissions)) + INTERVAL 1 DAY
  GROUP BY hadm_id
),
quartiles AS (
  SELECT hadm_id, 
         NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM med_complexity
),
outcomes AS (
  SELECT 
    q.hadm_id,
    q.quartile,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    a.hospital_expire_flag AS in_hospital_mortality,
    CASE 
      WHEN LEAD(a.admittime, 1) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) <= a.dischtime + INTERVAL 30 DAY THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM quartiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
)
SELECT 
  quartile,
  COUNT(*) AS count,
  AVG(los_hours) AS avg_los_hours,
  AVG(in_hospital_mortality) * 100 AS in_hospital_mortality_pct,
  AVG(readmitted_30d) * 100 AS readmitted_30d_pct
FROM outcomes
GROUP BY quartile
ORDER BY quartile;