WITH patients_f AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age >= 50
    AND anchor_age <= 60
),
first_adm AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS adm_rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_f pf ON a.subject_id = pf.subject_id
),
anticoag_hadms AS (
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN first_adm fa ON p.hadm_id = fa.hadm_id AND fa.adm_rn = 1
  WHERE p.starttime BETWEEN fa.admittime AND fa.dischtime
    AND (
      LOWER(p.drug) LIKE '%heparin%'
      OR LOWER(p.drug) LIKE '%warfarin%'
      OR LOWER(p.drug) LIKE '%enoxaparin%' OR LOWER(p.drug) LIKE '%lovenox%'
      OR LOWER(p.drug) LIKE '%dalteparin%' OR LOWER(p.drug) LIKE '%fragmin%'
      OR LOWER(p.drug) LIKE '%argatroban%'
      OR LOWER(p.drug) LIKE '%bivalirudin%' OR LOWER(p.drug) LIKE '%angiomax%'
      OR LOWER(p.drug) LIKE '%fondaparinux%' OR LOWER(p.drug) LIKE '%arixtra%'
      OR LOWER(p.drug) LIKE '%rivaroxaban%' OR LOWER(p.drug) LIKE '%xarelto%'
      OR LOWER(p.drug) LIKE '%apixaban%' OR LOWER(p.drug) LIKE '%eliquis%'
      OR LOWER(p.drug) LIKE '%dabigatran%' OR LOWER(p.drug) LIKE '%pradaxa%'
    )
),
first_icu AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime ASC) AS stay_rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN first_adm fa ON i.hadm_id = fa.hadm_id AND fa.adm_rn = 1
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los_days
FROM first_icu fi
INNER JOIN anticoag_hadms ah ON fi.hadm_id = ah.hadm_id
WHERE fi.stay_rn = 1;