WITH cabg_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS cabg_admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi ON a.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND d.long_title LIKE '%Coronary Artery Bypass%'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
),
first_cabg_admission AS (
  SELECT
    subject_id,
    hadm_id
  FROM cabg_admissions
  WHERE cabg_admission_seq = 1
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS icu_stay_seq
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN first_cabg_admission f ON i.hadm_id = f.hadm_id
)
SELECT
  AVG(los) AS mean_icu_los_days
FROM first_icu_stay
WHERE icu_stay_seq = 1;