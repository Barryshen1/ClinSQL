WITH male_50_60 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 50 AND 60
),
chestpain_ami_adm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chest pain%'
     OR LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
earliest_troponin AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum,
         ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_itemids ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
)
SELECT
  COUNT(DISTINCT e.subject_id) AS patient_count,
  COUNT(DISTINCT e.hadm_id) AS admission_count,
  AVG(e.valuenum) AS mean_hs_tnt,
  APPROX_QUANTILES(e.valuenum, 100)[OFFSET(50)] AS median_hs_tnt,
  (
    APPROX_QUANTILES(e.valuenum, 100)[OFFSET(75)]
    - APPROX_QUANTILES(e.valuenum, 100)[OFFSET(25)]
  ) AS iqr_hs_tnt
FROM earliest_troponin e
JOIN male_50_60 p
  ON e.subject_id = p.subject_id
JOIN chestpain_ami_adm ca
  ON e.subject_id = ca.subject_id
 AND e.hadm_id = ca.hadm_id
WHERE e.rn = 1
  AND e.valuenum > 0.014;