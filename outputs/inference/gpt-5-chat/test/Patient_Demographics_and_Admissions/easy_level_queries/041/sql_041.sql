WITH female_50_60 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),
first_admission AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_50_60 p
    ON a.subject_id = p.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
anticoagulant_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%heparin%'
     OR LOWER(drug) LIKE '%warfarin%'
     OR LOWER(drug) LIKE '%apixaban%'
     OR LOWER(drug) LIKE '%rivaroxaban%'
     OR LOWER(drug) LIKE '%dabigatran%'
     OR LOWER(drug) LIKE '%enoxaparin%'
     OR LOWER(drug) LIKE '%anticoagulant%'
),
first_icu_stay AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
)
SELECT
  APPROX_QUANTILES(f.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM first_admission fa
JOIN anticoagulant_admissions aa
  ON fa.hadm_id = aa.hadm_id
JOIN first_icu_stay f
  ON fa.hadm_id = f.hadm_id
;