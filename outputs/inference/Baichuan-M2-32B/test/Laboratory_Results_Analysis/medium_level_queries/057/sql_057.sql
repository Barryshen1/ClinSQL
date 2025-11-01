WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 79 AND 89
),
acs_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.age_at_admission
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I24.%'
    AND d.icd_code < 'I25'
),
troponin_measurements AS (
  SELECT
    t.hadm_id,
    t.valuenum,
    ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY t.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` t
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON t.itemid = d.itemid
  WHERE d.label LIKE '%TROPONIN T%'  -- Fixed: replaced loinc_code with label
    AND t.valueuom = 'ng/mL'
),
first_troponin AS (
  SELECT
    tm.hadm_id,
    tm.valuenum
  FROM troponin_measurements tm
  WHERE tm.rn = 1
)
SELECT
  CASE
    WHEN ft.valuenum <= 0.04 THEN 'Normal'
    WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'Borderline'
    WHEN ft.valuenum > 0.1 THEN 'Elevated'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS admission_count
FROM acs_admissions aa
INNER JOIN first_troponin ft
  ON aa.hadm_id = ft.hadm_id
GROUP BY troponin_category
ORDER BY troponin_category;