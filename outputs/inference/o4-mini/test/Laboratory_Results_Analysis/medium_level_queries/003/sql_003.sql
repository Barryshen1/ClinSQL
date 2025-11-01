WITH hs_tn_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%high sensitivity troponin t%'
),
female_ages AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
),
ihd_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%ischemic heart disease%'
),
initial_hs_tn AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    le.valuenum
  FROM female_ages f
  JOIN ihd_admissions ihd
    ON f.subject_id = ihd.subject_id
   AND f.hadm_id    = ihd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON f.subject_id = le.subject_id
   AND f.hadm_id    = le.hadm_id
  JOIN hs_tn_itemids hsi
    ON le.itemid     = hsi.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valuenum > le.ref_range_upper
    -- pick the first Troponin measurement per admission
    AND le.charttime = (
      SELECT MIN(le2.charttime)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le2
      WHERE le2.subject_id = le.subject_id
        AND le2.hadm_id    = le.hadm_id
        AND le2.itemid     = le.itemid
    )
)
SELECT
  arr[OFFSET(1)] AS p25,
  arr[OFFSET(2)] AS p50,
  arr[OFFSET(3)] AS p75,
  arr[OFFSET(0)] AS min_value,
  arr[OFFSET(4)] AS max_value
FROM (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS arr
  FROM initial_hs_tn
);