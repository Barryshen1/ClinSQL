WITH first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )
  WHERE rn = 1
),
dapt_patients AS (
  SELECT 
    fa.subject_id
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fa.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON fa.hadm_id = pr.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
  GROUP BY fa.subject_id
  HAVING 
    SUM(CASE WHEN LOWER(pr.drug) LIKE '%aspirin%' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE 
      WHEN LOWER(pr.drug) LIKE '%clopidogrel%' 
        OR LOWER(pr.drug) LIKE '%prasugrel%' 
        OR LOWER(pr.drug) LIKE '%ticagrelor%' 
      THEN 1 ELSE 0 END) > 0
),
icu_los AS (
  SELECT 
    fa.subject_id,
    SUM(ie.los) AS total_icu_los
  FROM first_admissions fa
  INNER JOIN dapt_patients dp ON fa.subject_id = dp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON fa.hadm_id = ie.hadm_id
  GROUP BY fa.subject_id
)
SELECT 
  AVG(total_icu_los) AS avg_icu_los_days
FROM icu_los;