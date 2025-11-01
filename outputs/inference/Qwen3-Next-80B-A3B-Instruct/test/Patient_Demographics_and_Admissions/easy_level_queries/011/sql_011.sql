WITH first_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.admissions
),
dapt_patients AS (
  SELECT 
    p.subject_id,
    p.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  WHERE LOWER(p.drug) IN (
    'aspirin', 'acetylsalicylic acid', 'asa', 
    'clopidogrel', 'plavix',
    'ticagrelor', 'brilinta',
    'prasugrel', 'effient'
  )
  GROUP BY p.subject_id, p.hadm_id
  HAVING COUNT(DISTINCT LOWER(p.drug)) >= 2
),
filtered_patients AS (
  SELECT 
    pa.subject_id,
    fa.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients pa
  INNER JOIN first_admission fa ON pa.subject_id = fa.subject_id
  INNER JOIN dapt_patients dp ON pa.subject_id = dp.subject_id AND fa.hadm_id = dp.hadm_id
  WHERE pa.gender = 'M' 
    AND pa.anchor_age BETWEEN 76 AND 86
    AND fa.rn = 1
)
SELECT 
  AVG(i.los) AS avg_icu_los_days
FROM filtered_patients fp
INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i 
  ON fp.subject_id = i.subject_id AND fp.hadm_id = i.hadm_id;