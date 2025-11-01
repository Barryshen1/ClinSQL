WITH ischemic AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    (di.icd_version = 9 AND (
        di.icd_code LIKE '410%' OR
        di.icd_code LIKE '411%' OR
        di.icd_code LIKE '412%' OR
        di.icd_code LIKE '413%' OR
        di.icd_code LIKE '414%'
    ))
    OR
    (di.icd_version = 10 AND (
        di.icd_code LIKE 'I20%' OR
        di.icd_code LIKE 'I21%' OR
        di.icd_code LIKE 'I22%' OR
        di.icd_code LIKE 'I23%' OR
        di.icd_code LIKE 'I24%' OR
        di.icd_code LIKE 'I25%'
    ))
),
female_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 36 AND 46
),
hs_tnt AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum,
         CAST(le.ref_range_upper AS FLOAT64) AS ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%' 
    AND LOWER(dl.label) LIKE '%high sensitivity%'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
first_hs_tnt AS (
  SELECT subject_id, hadm_id, valuenum, ref_range_upper
  FROM (
    SELECT h.subject_id, h.hadm_id, h.valuenum, h.ref_range_upper,
           ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY h.charttime) AS rn
    FROM hs_tnt h
    JOIN ischemic i
      ON h.subject_id = i.subject_id AND h.hadm_id = i.hadm_id
    JOIN female_age f
      ON h.subject_id = f.subject_id
  )
  WHERE rn = 1
    AND valuenum > ref_range_upper
)
SELECT
  MIN(valuenum) AS min_value,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MAX(valuenum) AS max_value
FROM first_hs_tnt;