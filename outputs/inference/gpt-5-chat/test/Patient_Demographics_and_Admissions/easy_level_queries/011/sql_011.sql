WITH first_admission AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT subject_id, hadm_id, admittime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a
  ON p.subject_id = a.subject_id
  WHERE a.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
antiplatelet_rx AS (
  SELECT DISTINCT
    hadm_id,
    LOWER(drug) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%aspirin%'
     OR LOWER(drug) LIKE '%clopidogrel%'
     OR LOWER(drug) LIKE '%ticagrelor%'
     OR LOWER(drug) LIKE '%prasugrel%'
     OR LOWER(drug) LIKE '%dipyridamole%'
),
dapt_hadm AS (
  SELECT
    hadm_id
  FROM antiplatelet_rx
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT drug_name) >= 2
),
icu_los_per_patient AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    AVG(icu.los) AS avg_icu_los_days
  FROM first_admission fa
  JOIN dapt_hadm dapt
    ON fa.hadm_id = dapt.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON fa.subject_id = icu.subject_id
   AND fa.hadm_id = icu.hadm_id
  GROUP BY fa.subject_id, fa.hadm_id
)
SELECT
  AVG(avg_icu_los_days) AS average_icu_los_days_for_first_admission
FROM icu_los_per_patient;