WITH sepsis_adm AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
platelet_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
),
first_platelets AS (
  SELECT
    s.hadm_id,
    MIN(le.charttime) AS first_charttime
  FROM sepsis_adm s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = s.hadm_id
  JOIN platelet_items pi
    ON pi.itemid = le.itemid
  WHERE le.charttime BETWEEN s.admittime
                          AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
  GROUP BY s.hadm_id
),
adm_platelet AS (
  SELECT
    f.hadm_id,
    le.valuenum AS platelet_count
  FROM first_platelets f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = f.hadm_id
   AND le.charttime = f.first_charttime
  JOIN platelet_items pi
    ON le.itemid = pi.itemid
)
SELECT
  STDDEV_SAMP(platelet_count) AS platelet_stddev
FROM adm_platelet;