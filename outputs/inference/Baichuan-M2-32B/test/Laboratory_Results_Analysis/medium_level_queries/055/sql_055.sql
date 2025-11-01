WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR) + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR) + p.anchor_age BETWEEN 81 AND 91
    AND a.dischtime IS NOT NULL
),
diagnoses AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    diag.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%chest pain%' 
     OR LOWER(diag.long_title) LIKE '%myocardial infarction%'
),
hs_tnt_labs AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  INNER JOIN patient_admissions pa
    ON l.subject_id = pa.subject_id AND l.hadm_id = pa.hadm_id
  WHERE (li.label LIKE '%hs-TnT%' OR li.label LIKE '%high-sensitivity Troponin T%')
    AND li.unitname = 'ng/L'
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN pa.admittime AND pa.dischtime
),
first_hs_tnt AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum
  FROM hs_tnt_labs
  WHERE rn = 1
),
admissions_with_diagnosis AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.age_at_admission,
    fht.valuenum AS hs_tnt_value
  FROM patient_admissions pa
  INNER JOIN diagnoses d 
    ON pa.subject_id = d.subject_id AND pa.hadm_id = d.hadm_id
  INNER JOIN first_hs_tnt fht 
    ON pa.subject_id = fht.subject_id AND pa.hadm_id = fht.hadm_id
),
hs_tnt_categories AS (
  SELECT 
    subject_id,
    hadm_id,
    hs_tnt_value,
    CASE 
      WHEN hs_tnt_value < 14 THEN 'normal'
      WHEN hs_tnt_value BETWEEN 14 AND 50 THEN 'borderline'
      WHEN hs_tnt_value > 50 THEN 'myocardial injury'
      ELSE 'unknown' 
    END AS hs_tnt_category,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM admissions_with_diagnosis
)
SELECT 
  hs_tnt_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los), 2) AS mean_los
FROM hs_tnt_categories
GROUP BY hs_tnt_category
ORDER BY hs_tnt_category;