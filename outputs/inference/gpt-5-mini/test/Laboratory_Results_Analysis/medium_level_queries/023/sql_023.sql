WITH acs_hadm AS (
  -- admissions that have an ACS-related diagnosis (matches ICD long_title text)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code
   AND d.icd_version = diag.icd_version
  WHERE LOWER(diag.long_title) LIKE '%acute%'
    AND (
      LOWER(diag.long_title) LIKE '%myocardial%'
      OR LOWER(diag.long_title) LIKE '%unstable angina%'
      OR LOWER(diag.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(diag.long_title) LIKE '%coronary%'
    )
),

cohort AS (
  -- female patients aged 67-77 at admission with an ACS diagnosis
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_hadm ac
    ON a.hadm_id = ac.hadm_id
  WHERE p.anchor_age BETWEEN 67 AND 77
    AND LOWER(p.gender) LIKE 'f%'   -- matches 'F' or 'Female'
),

trop_items AS (
  -- Troponin T lab item(s) by label text
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%trop t%'
     OR LOWER(label) LIKE '%troponin-t%'
),

first_trop AS (
  -- earliest Troponin T measurement during the admission (if any)
  SELECT
    c.hadm_id,
    c.subject_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN trop_items ti
    ON le.itemid = ti.itemid
  JOIN cohort c
    ON le.hadm_id = c.hadm_id
   AND le.charttime BETWEEN c.admittime AND c.dischtime
)

SELECT
  category,
  COUNT(*) AS admissions_count,
  ROUND(SAFE_MULTIPLY(SAFE_DIVIDE(COUNT(*), total.total_admissions), 100), 2) AS percent_of_cohort,
  ROUND(SAFE_MULTIPLY(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 100), 2) AS in_hospital_mortality_pct
FROM (
  -- tie cohort to its initial Troponin T (if any) and classify
  SELECT
    c.hadm_id,
    c.subject_id,
    c.hospital_expire_flag,
    ft.valuenum,
    CASE
      WHEN ft.hadm_id IS NULL THEN 'missing'
      WHEN ft.valuenum IS NULL THEN 'missing'
      WHEN ft.valuenum <= 0.04 THEN '≤0.04 normal'
      WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN '>0.04–0.1 borderline'
      WHEN ft.valuenum > 0.1 THEN '>0.1 elevated'
      ELSE 'missing'
    END AS category
  FROM cohort c
  LEFT JOIN (
    SELECT hadm_id, valuenum
    FROM first_trop
    WHERE rn = 1
  ) ft
  ON c.hadm_id = ft.hadm_id
) AS classified
CROSS JOIN (
  -- total number of admissions in the cohort for percent calculations
  SELECT COUNT(*) AS total_admissions
  FROM cohort
) AS total
GROUP BY category, total.total_admissions
ORDER BY
  -- present categories in a sensible order
  CASE
    WHEN category = '≤0.04 normal' THEN 1
    WHEN category = '>0.04–0.1 borderline' THEN 2
    WHEN category = '>0.1 elevated' THEN 3
    WHEN category = 'missing' THEN 4
    ELSE 5
  END;