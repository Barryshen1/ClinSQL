WITH men_76_86 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),
first_admissions AS (
  SELECT p.subject_id, a.hadm_id, a.admittime
  FROM men_76_86 p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
antiplatelet_rx AS (
  -- List of antiplatelet drugs (lowercase for matching)
  SELECT
    fa.subject_id,
    fa.hadm_id,
    COUNT(DISTINCT LOWER(pr.drug)) AS num_antiplatelets
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON fa.subject_id = pr.subject_id AND fa.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%aspirin%'
     OR LOWER(pr.drug) LIKE '%clopidogrel%'
     OR LOWER(pr.drug) LIKE '%ticagrelor%'
     OR LOWER(pr.drug) LIKE '%prasugrel%'
     OR LOWER(pr.drug) LIKE '%dipyridamole%'
     OR LOWER(pr.drug) LIKE '%ticlopidine%'
     OR LOWER(pr.drug) LIKE '%cilostazol%'
     OR LOWER(pr.drug) LIKE '%abciximab%'
     OR LOWER(pr.drug) LIKE '%eptifibatide%'
     OR LOWER(pr.drug) LIKE '%tirofiban%'
  GROUP BY fa.subject_id, fa.hadm_id
  HAVING num_antiplatelets >= 2
),
first_icu_stay AS (
  SELECT
    arx.subject_id,
    arx.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM antiplatelet_rx arx
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON arx.subject_id = icu.subject_id AND arx.hadm_id = icu.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY arx.subject_id, arx.hadm_id ORDER BY icu.intime) = 1
)
SELECT
  COUNT(*) AS n_patients,
  AVG(los) AS avg_icu_los_days
FROM first_icu_stay;