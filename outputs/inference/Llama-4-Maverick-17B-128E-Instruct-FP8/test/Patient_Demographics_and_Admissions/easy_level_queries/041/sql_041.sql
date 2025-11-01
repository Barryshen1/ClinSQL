WITH cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
),
first_icu_stay AS (
  SELECT i.subject_id, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE i.subject_id IN (SELECT subject_id FROM cohort)
  AND a.admittime = (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE subject_id = i.subject_id)
  AND i.intime = (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = i.hadm_id)
),
anticoagulant_users AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug_type = 'MAIN' AND (LOWER(drug) LIKE '%warfarin%' OR LOWER(drug) LIKE '%heparin%' OR LOWER(drug) LIKE '%coumarin%')
),
final_cohort AS (
  SELECT f.subject_id, f.los
  FROM first_icu_stay f
  JOIN anticoagulant_users a ON f.subject_id = a.subject_id
)
SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los
FROM final_cohort;