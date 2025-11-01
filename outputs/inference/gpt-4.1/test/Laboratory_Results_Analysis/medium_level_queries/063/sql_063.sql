WITH acs_icd AS (
  -- ICD codes for ACS (ICD-9: 410, 411, 413; ICD-10: I20, I21, I22, I23)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (d.icd_version = 9 AND (
      LEFT(d.icd_code,3) IN ('410','411','413')
    )) OR
    (d.icd_version = 10 AND (
      LEFT(d.icd_code,3) IN ('I20','I21','I22','I23')
    ))
  )
),
troponin_i_items AS (
  -- Find itemid(s) for Troponin I
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),
initial_trop AS (
  -- Get initial Troponin I per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_i_items t ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
)
SELECT
  COUNT(*) AS admission_count,
  AVG(init.valuenum) AS mean_initial_troponin_i,
  APPROX_QUANTILES(init.valuenum, 2)[OFFSET(1)] AS median_initial_troponin_i,
  APPROX_QUANTILES(init.valuenum, 4)[OFFSET(1)] AS troponin_i_25th_percentile,
  APPROX_QUANTILES(init.valuenum, 4)[OFFSET(3)] AS troponin_i_75th_percentile
FROM initial_trop init
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON init.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON init.subject_id = pat.subject_id
JOIN acs_icd acs ON init.hadm_id = acs.hadm_id
WHERE
  init.rn = 1 -- only initial Troponin I per admission
  AND LOWER(pat.gender) = 'female'
  AND pat.anchor_age BETWEEN 84 AND 94
  -- Troponin I must exceed 99th percentile ULN (use ref_range_upper if available, else assume 0.04)
  AND (
    (init.ref_range_upper IS NOT NULL AND init.valuenum > init.ref_range_upper)
    OR
    (init.ref_range_upper IS NULL AND init.valuenum > 0.04)
  );