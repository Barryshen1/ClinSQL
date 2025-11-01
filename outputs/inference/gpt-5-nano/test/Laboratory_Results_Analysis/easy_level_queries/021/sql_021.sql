WITH male_pneumonia_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'Male'
    AND LOWER(d.long_title) LIKE '%pneumonia%'
    AND a.dischtime IS NOT NULL
),
glucose_per_admission AS (
  SELECT m.hadm_id, l.charttime, l.valuenum
  FROM male_pneumonia_admissions AS m
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON m.subject_id = l.subject_id AND m.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON l.itemid = li.itemid
  WHERE l.charttime <= m.dischtime
    AND LOWER(li.label) LIKE '%glucose%'
    AND LOWER(li.fluid) LIKE '%serum%'
),
last_glucose AS (
  SELECT hadm_id, MAX(charttime) AS last_charttime
  FROM glucose_per_admission
  GROUP BY hadm_id
),
last_glucose_values AS (
  SELECT l.valuenum
  FROM last_glucose lg
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = lg.hadm_id AND l.charttime = lg.last_charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON l.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%glucose%'
    AND LOWER(li.fluid) LIKE '%serum%'
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(74)] AS glucose_75th_percentile
FROM last_glucose_values;