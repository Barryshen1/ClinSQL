WITH pneumonia_males AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) IN ('m', 'male')
    AND di.icd_version = 9
    AND di.icd_code LIKE '48%'
),
glucose_within24 AS (
  SELECT
    pm.hadm_id,
    le.valuenum
  FROM pneumonia_males pm
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = pm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = a.subject_id
   AND le.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(dli.label) LIKE '%glucose%'
    AND LOWER(dli.fluid) LIKE '%serum%'
    -- first 24 hours from admission
    AND le.charttime >= a.admittime
    AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
),
per_admission AS (
  SELECT hadm_id, AVG(valuenum) AS mean_glucose
  FROM glucose_within24
  GROUP BY hadm_id
  HAVING AVG(valuenum) IS NOT NULL
)
SELECT
  quantiles[OFFSET(74)] AS p75_mean_glucose
FROM (
  SELECT APPROX_QUANTILES(mean_glucose, 100) AS quantiles
  FROM per_admission
  WHERE mean_glucose IS NOT NULL
);