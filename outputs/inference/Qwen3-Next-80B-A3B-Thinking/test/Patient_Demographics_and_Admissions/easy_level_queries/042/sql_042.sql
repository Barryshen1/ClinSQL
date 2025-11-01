WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr ON pr.icd_code = dpr.icd_code AND pr.icd_version = dpr.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON pr.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND dpr.long_title LIKE '%CABG%'
),
first_cabg AS (
  SELECT 
    subject_id,
    hadm_id,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM eligible_patients
),
icu_stays AS (
  SELECT 
    f.hadm_id,
    SUM(TIMESTAMP_DIFF(i.outtime, i.intime, SECOND) / 86400.0) AS total_los_days
  FROM first_cabg f
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON f.hadm_id = i.hadm_id
  WHERE f.rn = 1
  GROUP BY f.hadm_id
)
SELECT AVG(total_los_days) AS mean_icu_los
FROM icu_stays;