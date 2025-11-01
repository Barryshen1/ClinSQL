WITH hemorrhagic_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 87
    AND LOWER(dd.long_title) LIKE '%hemorrhag%'
),
platelet_items AS (
  SELECT
    itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
    AND LOWER(category) LIKE '%hematology%'
),
discharge_platelets AS (
  SELECT
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN hemorrhagic_patients AS hp
    ON le.subject_id = hp.subject_id
   AND le.hadm_id    = hp.hadm_id
  JOIN platelet_items AS pi
    ON le.itemid = pi.itemid
  WHERE DATE(le.charttime) = DATE(hp.dischtime)
    AND le.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75_platelet_count
FROM discharge_platelets;