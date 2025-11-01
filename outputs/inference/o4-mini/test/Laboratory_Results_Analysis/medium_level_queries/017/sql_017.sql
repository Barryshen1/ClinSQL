WITH ischemic_adms AS (
  SELECT DISTINCT d.subject_id,
                  d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE d.icd_version = 10
    AND dicd.icd_code BETWEEN 'I20' AND 'I25'
    AND d.seq_num = 1
),
male_midage_adms AS (
  SELECT p.subject_id,
         a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
),
trop_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT le.subject_id,
         le.hadm_id,
         MIN(le.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN trop_itemids t
    ON le.itemid = t.itemid
  GROUP BY le.subject_id, le.hadm_id
),
first_troponin_values AS (
  SELECT ft.subject_id,
         ft.hadm_id,
         le.valuenum AS first_tn_val
  FROM first_troponin ft
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ft.subject_id = le.subject_id
   AND ft.hadm_id = le.hadm_id
   AND ft.first_charttime = le.charttime
  WHERE le.valuenum IS NOT NULL
)
SELECT
  qs[OFFSET(1)] AS q1_troponin,
  qs[OFFSET(2)] AS median_troponin,
  qs[OFFSET(3)] AS q3_troponin
FROM (
  SELECT APPROX_QUANTILES(first_tn_val, 4) AS qs
  FROM first_troponin_values fv
  JOIN ischemic_adms ia
    ON fv.subject_id = ia.subject_id
   AND fv.hadm_id    = ia.hadm_id
  JOIN male_midage_adms mma
    ON fv.subject_id = mma.subject_id
   AND fv.hadm_id    = mma.hadm_id
  WHERE fv.first_tn_val > 0.014
);