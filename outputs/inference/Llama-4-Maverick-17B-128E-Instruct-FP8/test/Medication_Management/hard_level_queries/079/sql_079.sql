WITH patient_info AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    COUNT(DISTINCT pr.drug) AS unique_drugs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.hadm_id = pr.hadm_id AND pr.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 7 DAY
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 89 AND 99
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_version = 10 AND icd_code LIKE 'I61%' 
         OR icd_version = 9 AND icd_code BETWEEN '431' AND '432'
    )
  GROUP BY 
    p.subject_id, a.hadm_id, p.gender, a.admittime, a.dischtime, a.deathtime, age
),
med_complexity AS (
  SELECT 
    subject_id,
    hadm_id,
    unique_drugs,
    NTILE(5) OVER (ORDER BY unique_drugs) AS quintile
  FROM 
    patient_info
),
outcomes AS (
  SELECT 
    mc.quintile,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR)) / 24 AS avg_los,
    SUM(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS inpatient_mortality,
    SUM(CASE 
          WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
            WHERE a2.subject_id = a.subject_id 
              AND a2.admittime > a.dischtime 
              AND DATETIME_DIFF(a2.admittime, a.dischtime, DAY) <= 30
          ) THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS readmission_rate
  FROM 
    med_complexity mc
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON mc.hadm_id = a.hadm_id
  GROUP BY 
    mc.quintile
)
SELECT 
  quintile,
  avg_los,
  inpatient_mortality,
  readmission_rate
FROM 
  outcomes
ORDER BY 
  quintile;