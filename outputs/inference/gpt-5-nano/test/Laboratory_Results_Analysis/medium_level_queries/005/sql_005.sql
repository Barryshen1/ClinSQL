WITH
  -- Identify hs-cTnT measurements (label contains troponin and hs/high-sensitivity)
  hs_troponin AS (
    SELECT
      le.hadm_id,
      le.charttime,
      le.valuenum,
      le.valueuom
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE LOWER(dli.label) LIKE '%troponin%'
      AND (LOWER(dli.label) LIKE '%hs%' OR LOWER(dli.label) LIKE '%high sensitivity%')
      AND le.valuenum IS NOT NULL
      AND (LOWER(le.valueuom) LIKE '%ng/l%')
  ),

  -- First hs-cTnT measurement per admission
  first_hs_tn AS (
    SELECT hadm_id, charttime, valuenum
    FROM (
      SELECT
        hst.hadm_id,
        hst.charttime,
        hst.valuenum,
        ROW_NUMBER() OVER (PARTITION BY hst.hadm_id ORDER BY hst.charttime) AS rn
      FROM hs_troponin AS hst
    )
    WHERE rn = 1
  ),

  -- Valid first hs-cTnT measurements that fall inside the admission window
  valid_first_tn AS (
    SELECT
      fh.hadm_id,
      fh.charttime,
      fh.valuenum
    FROM first_hs_tn AS fh
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON fh.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE fh.charttime >= a.admittime
      AND (a.dischtime IS NULL OR fh.charttime <= a.dischtime)
      AND p.gender = 'Male'
      AND p.anchor_age BETWEEN 35 AND 45
  ),

  -- Hadm IDs with chest pain or myocardial infarction diagnosis
  hadm_chest_pain AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
      ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
    WHERE LOWER(ddi.long_title) LIKE '%chest pain%'
       OR LOWER(ddi.long_title) LIKE '%myocardial infarction%'
  )

SELECT
  CASE
    WHEN t.valuenum < 5 THEN 'normal'
    WHEN t.valuenum >= 5 AND t.valuenum <= 14 THEN 'borderline'
    WHEN t.valuenum > 14 THEN 'myocardial injury'
    ELSE 'unknown'
  END AS category,
  COUNT(*) AS count
FROM valid_first_tn AS t
JOIN hadm_chest_pain AS hcp
  ON t.hadm_id = hcp.hadm_id
GROUP BY category
ORDER BY category;