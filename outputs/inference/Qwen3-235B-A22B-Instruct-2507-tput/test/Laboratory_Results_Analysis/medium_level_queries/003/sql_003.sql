WITH patient_admissions AS (
  SELECT p.subject_id, p.gender, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 36 AND 46
),

ihd_admissions AS (
  SELECT pa.subject_id, pa.hadm_id, pa.admittime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.seq_num = 1  -- primary diagnosis
    AND d.icd_code LIKE 'I20%'
    OR d.icd_code LIKE 'I21%'
    OR d.icd_code LIKE 'I22%'
    OR d.icd_code LIKE 'I23%'
    OR d.icd_code LIKE 'I24%'
    OR d.icd_code LIKE 'I25%'
),

troponin_lab AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin t high sensitive'
),

first_elevated_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN troponin_lab t
    ON le.itemid = t.itemid
  INNER JOIN ihd_admissions ia
    ON le.hadm_id = ia.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.valuenum > le.ref_range_upper
    AND le.charttime >= ia.admittime  -- only after admission
)

SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM first_elevated_troponin
WHERE rn = 1;