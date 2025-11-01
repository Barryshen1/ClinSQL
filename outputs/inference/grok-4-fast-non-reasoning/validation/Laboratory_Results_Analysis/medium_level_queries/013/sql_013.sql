WITH qualifying_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND CAST(d.seq_num AS INT64) = 1
    AND d.seq_num IS NOT NULL
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      -- Chest pain (ICD-10 R07.*)
      (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^R07'))
      OR 
      -- AMI (ICD-10 I21.* or ICD-9 410.*)
      (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^I21'))
      OR 
      (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^410'))
    )
),
initial_hstnt AS (
  SELECT 
    qa.subject_id,
    qa.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY le.charttime ASC) as rn
  FROM 
    qualifying_admissions qa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON qa.hadm_id = le.hadm_id
    AND le.charttime >= qa.admittime
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE 
    -- Correct itemid for hs-Troponin T (confirmed in d_labitems)
    le.itemid = 3616
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND li.category = 'Chemistry'
    AND li.label LIKE '%Troponin T%'
)
SELECT 
  COUNT(DISTINCT ih.subject_id) AS patient_count,
  COUNT(DISTINCT ih.hadm_id) AS admission_count,
  AVG(ih.valuenum) AS mean_hstnt,
  APPROX_QUANTILES(ih.valuenum, 4)[OFFSET(2)] AS median_hstnt,
  APPROX_QUANTILES(ih.valuenum, 4)[OFFSET(1)] AS iqr_lower,
  APPROX_QUANTILES(ih.valuenum, 4)[OFFSET(3)] AS iqr_upper
FROM 
  initial_hstnt ih
WHERE 
  ih.rn = 1  -- Initial lab per admission
  AND ih.valuenum > 0.014;  -- > ULN;