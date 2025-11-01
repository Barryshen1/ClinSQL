WITH acs_admissions AS (
  -- Admissions that have at least one diagnosis matching ACS terms
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON d.hadm_id = a.hadm_id
  WHERE (
    LOWER(dic.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dic.long_title) LIKE '%unstable angina%'
    OR LOWER(dic.long_title) LIKE '%acute coronary%'
    OR LOWER(dic.long_title) LIKE '%stemi%'
    OR LOWER(dic.long_title) LIKE '%nstemi%'
  )
),
male_acs_admissions AS (
  -- Restrict to male patients
  SELECT aa.subject_id, aa.hadm_id
  FROM acs_admissions aa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON aa.subject_id = p.subject_id
  WHERE p.gender = 'M'
  -- If you want to restrict to age 57, uncomment:
  -- AND p.anchor_age = 57
),
troponin_items AS (
  -- Lab items that likely correspond to troponin assays
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),
troponin_measurements AS (
  -- All troponin lab measurements for male ACS admissions, with numeric value extraction
  SELECT
    le.subject_id,
    le.hadm_id,
    le.labevent_id,
    le.itemid,
    dli.label AS lab_label,
    le.charttime,
    le.value,
    le.valueuom,
    le.valuenum,
    -- prefer valuenum; otherwise try to coerce numeric characters from value text
    COALESCE(
      le.valuenum,
      SAFE_CAST(REGEXP_REPLACE(COALESCE(le.value, ''), r'[^0-9\.\-eE\+]', '') AS FLOAT64)
    ) AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items dli
    ON le.itemid = dli.itemid
  JOIN male_acs_admissions maa
    ON le.hadm_id = maa.hadm_id
  WHERE le.hadm_id IS NOT NULL
),
troponin_filtered AS (
  -- Keep only rows where we successfully obtained a numeric troponin
  SELECT *
  FROM troponin_measurements
  WHERE troponin_value IS NOT NULL
),
overall_min AS (
  SELECT
    MIN(troponin_value) AS min_troponin,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    COUNT(*) AS n_measurements
  FROM troponin_filtered
),
min_example AS (
  -- Provide one example row that equals the minimum (earliest charttime if multiple)
  SELECT tf.*
  FROM troponin_filtered tf
  JOIN overall_min om ON tf.troponin_value = om.min_troponin
  ORDER BY tf.charttime ASC
  LIMIT 1
)
SELECT
  om.min_troponin AS minimum_troponin_value,
  me.lab_label AS example_lab_label,
  me.valueuom AS example_value_unit,
  me.charttime AS example_charttime,
  me.subject_id AS example_subject_id,
  me.hadm_id AS example_hadm_id,
  om.n_admissions,
  om.n_measurements
FROM overall_min om
LEFT JOIN min_example me ON TRUE;