WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 43 AND 53
),
acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE (
    -- ICD-10 ACS codes: I20, I21, I22, I23, I24
    (d.icd_version = 10 AND (
      REGEXP_CONTAINS(d.icd_code, r'^I20') OR
      REGEXP_CONTAINS(d.icd_code, r'^I21') OR
      REGEXP_CONTAINS(d.icd_code, r'^I22') OR
      REGEXP_CONTAINS(d.icd_code, r'^I23') OR
      REGEXP_CONTAINS(d.icd_code, r'^I24')
    ))
    -- ICD-9 equivalents: 410 (AMI), 411 (other ACS), 413 (angina)
    OR (d.icd_version = 9 AND (
      REGEXP_CONTAINS(d.icd_code, r'^410') OR
      REGEXP_CONTAINS(d.icd_code, r'^411') OR
      REGEXP_CONTAINS(d.icd_code, r'^413')
    ))
  )
),
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) NOT LIKE '%troponin i%' -- exclude Troponin I
),
initial_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    -- Convert all values to ng/mL
    CASE
      WHEN LOWER(l.valueuom) = 'ng/ml' THEN l.valuenum
      WHEN LOWER(l.valueuom) = 'ng/l' THEN l.valuenum / 1000
      ELSE NULL
    END AS troponin_ngml
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN acs_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN troponin_itemids t ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
    AND (LOWER(l.valueuom) = 'ng/ml' OR LOWER(l.valueuom) = 'ng/l')
),
first_troponin AS (
  -- Get the first (earliest) troponin value per admission
  SELECT
    subject_id,
    hadm_id,
    troponin_ngml,
    charttime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      troponin_ngml,
      charttime,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM initial_troponin
  )
  WHERE rn = 1
    AND troponin_ngml > 0.014 -- 99th percentile ULN
)
SELECT
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(troponin_ngml, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(troponin_ngml, 4)[OFFSET(1)] AS iqr_25,
  APPROX_QUANTILES(troponin_ngml, 4)[OFFSET(3)] AS iqr_75
FROM first_troponin;