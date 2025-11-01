WITH acs_admissions AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    -- identify ACS by keywords in diagnosis description
    LOWER(dd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dd.long_title) LIKE '%unstable angina%'
    OR LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
  GROUP BY
    d.subject_id,
    d.hadm_id
),
male_acs AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    acs_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON a.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'M'
),
troponin_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin%'
),
peak_troponin_per_admission AS (
  SELECT
    le.hadm_id,
    MAX(le.valuenum) AS peak_troponin
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti
      ON le.itemid = ti.itemid
    JOIN male_acs m
      ON le.hadm_id = m.hadm_id
  WHERE
    le.valuenum IS NOT NULL
  GROUP BY
    le.hadm_id
)
SELECT
  -- approximate 75th percentile of peak in-hospital troponin
  APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS troponin_75th_percentile
FROM
  peak_troponin_per_admission;