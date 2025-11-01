WITH troponin_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.storetime,
    le.valuenum,
    le.valueuom,
    dl.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime IS NOT NULL
),

first_troponin AS (
  -- earliest troponin T per hospital admission
  SELECT subject_id, hadm_id, valuenum AS first_troponin, charttime
  FROM (
    SELECT te.*,
      ROW_NUMBER() OVER (PARTITION BY te.hadm_id ORDER BY te.charttime ASC, te.storetime ASC) AS rn
    FROM troponin_events te
  )
  WHERE rn = 1
),

eligible_admissions AS (
  -- female patients age 58-68 with a diagnosis of chest pain or myocardial infarction
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      LOWER(dicd.long_title) LIKE '%chest pain%'
      OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
    )
)

SELECT
  COUNT(*) AS n_admissions,
  ROUND(AVG(ft.first_troponin), 4) AS mean_first_troponin,
  ROUND(STDDEV_SAMP(ft.first_troponin), 4) AS sd_first_troponin,
  MIN(ft.first_troponin) AS min_first_troponin,
  MAX(ft.first_troponin) AS max_first_troponin
FROM first_troponin ft
JOIN eligible_admissions ea
  ON ft.hadm_id = ea.hadm_id
WHERE ft.first_troponin > 0.01;