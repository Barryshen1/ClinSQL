WITH ischemic_male AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND dd.long_title LIKE '%ischemic%' AND dd.long_title LIKE '%stroke%'
),
glucose_serum AS (
  SELECT
    im.hadm_id,
    le.charttime,
    le.valuenum
  FROM ischemic_male AS im
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON im.subject_id = le.subject_id AND im.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE UPPER(dli.label) LIKE '%GLUCOSE%' AND dli.fluid = 'Serum' AND le.valuenum IS NOT NULL
),
discharge_glucose AS (
  SELECT
    g.hadm_id,
    g.charttime,
    g.valuenum,
    ROW_NUMBER() OVER (PARTITION BY g.hadm_id ORDER BY g.charttime DESC) AS rn
  FROM glucose_serum AS g
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON g.hadm_id = a.hadm_id
  WHERE DATE(g.charttime) = DATE(a.dischtime)
)
SELECT
  (PERCENTILE_CONT(valuenum, 0.75) OVER() - PERCENTILE_CONT(valuenum, 0.25) OVER()) AS iqr_serum_glucose_on_discharge
FROM discharge_glucose
WHERE rn = 1;