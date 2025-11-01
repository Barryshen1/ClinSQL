WITH
-- Get male patients aged 79-89
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 79 AND 89
),

-- Get admissions with ACS diagnosis (ICD-10 codes I20-I25)
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND d.icd_code BETWEEN 'I20' AND 'I25'
    AND d.icd_version = 10
),

-- Get Troponin T itemid (by label)
troponin_item AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    label LIKE '%Troponin T%'
),

-- Get first Troponin T measurement per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.valueuom,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) as rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    troponin_item t ON l.itemid = t.itemid
  WHERE
    l.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND l.valuenum IS NOT NULL
)

-- Final categorization and counts
SELECT
  troponin_category,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM (
  SELECT
    CASE
      WHEN ft.valuenum < ft.ref_range_upper THEN 'Normal'
      WHEN ft.valuenum <= ft.ref_range_upper * 1.5 THEN 'Borderline'
      ELSE 'Elevated'
    END as troponin_category
  FROM
    first_troponin ft
  WHERE
    ft.rn = 1
    AND ft.ref_range_upper IS NOT NULL
)
GROUP BY
  troponin_category
ORDER BY
  troponin_category;