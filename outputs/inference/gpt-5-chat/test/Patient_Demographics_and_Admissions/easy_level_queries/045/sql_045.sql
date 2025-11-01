WITH pneumonia_hadm AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    -- ICD-10 pneumonia J12–J18
    (d.icd_version = 10 AND (
         dd.icd_code LIKE 'J12%' OR dd.icd_code LIKE 'J13%' OR dd.icd_code LIKE 'J14%' OR
         dd.icd_code LIKE 'J15%' OR dd.icd_code LIKE 'J16%' OR dd.icd_code LIKE 'J17%' OR dd.icd_code LIKE 'J18%'
     ))
    OR
    -- ICD-9 pneumonia 480–486, 4870
    (d.icd_version = 9 AND (
         (SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486)
         OR d.icd_code = '4870'
     ))
),
first_admissions AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN pneumonia_hadm ph
    ON a.subject_id = ph.subject_id AND a.hadm_id = ph.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_adm_per_patient AS (
  SELECT fa.subject_id, fa.hadm_id
  FROM (
    SELECT subject_id, hadm_id,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM first_admissions
  ) fa
  WHERE rn = 1
),
first_icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN first_adm_per_patient fap
    ON i.subject_id = fap.subject_id AND i.hadm_id = fap.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY intime) = 1
)
SELECT
  PERCENTILE_CONT(los, 0.25) OVER() AS los_25th_percentile_days
FROM first_icu_stays;