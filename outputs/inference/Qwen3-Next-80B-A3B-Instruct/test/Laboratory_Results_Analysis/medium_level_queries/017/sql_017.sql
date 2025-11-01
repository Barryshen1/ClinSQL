WITH filtered_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND (
      LOWER(d_icd.long_title) LIKE '%ischemic heart disease%'
      OR LOWER(d_icd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(d_icd.long_title) LIKE '%angina%'
      OR d.icd_code BETWEEN 'I20' AND 'I25'
      OR (d.icd_version = 9 AND d.icd_code BETWEEN '410' AND '414')
    )
),

troponin_first_above_threshold AS (
  SELECT
    fp.subject_id,
    fp.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY fp.hadm_id ORDER BY le.charttime) AS rn
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fp.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.014
    AND LOWER(le.valueuom) IN ('ng/ml', 'ng/mL')
)

SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_troponin_t
FROM troponin_first_above_threshold
WHERE rn = 1;