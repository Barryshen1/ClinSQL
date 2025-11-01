WITH base_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),
cabg_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON pc.subject_id = a.subject_id AND pc.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON dp.icd_code = pc.icd_code AND dp.icd_version = pc.icd_version
  WHERE LOWER(dp.long_title) LIKE '%cabg%'
    AND a.subject_id IN (SELECT subject_id FROM base_patients)
),
first_cabg AS (
  SELECT subject_id, hadm_id, admittime
  FROM (
    SELECT c.subject_id, c.hadm_id, c.admittime,
           ROW_NUMBER() OVER (PARTITION BY c.subject_id ORDER BY c.admittime ASC) AS rn
    FROM cabg_admissions c
  )
  WHERE rn = 1
),
icu_los_per_admission AS (
  SELECT fc.subject_id, fc.hadm_id,
         SUM(i.los) AS icu_los_days
  FROM first_cabg fc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.subject_id = fc.subject_id AND i.hadm_id = fc.hadm_id
  GROUP BY fc.subject_id, fc.hadm_id
)
SELECT AVG(icu_los_days) AS mean_icu_los_days
FROM icu_los_per_admission;