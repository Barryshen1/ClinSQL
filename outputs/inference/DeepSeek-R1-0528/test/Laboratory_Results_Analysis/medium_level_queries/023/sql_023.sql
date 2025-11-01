WITH acs_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    -- ACS ICD-9: 410, 411, 413 (prefix)
    (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('410','411','413'))
    -- ACS ICD-10: I200 OR I21/I22/I23/I24 (prefix)
    OR (diag.icd_version = 10 AND (
        diag.icd_code = 'I200' OR 
        SUBSTR(diag.icd_code, 1, 3) IN ('I21','I22','I23','I24')
    ))
),
cohort AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND adm.hadm_id IN (SELECT hadm_id FROM acs_admissions)  -- ACS admissions only
),
first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id
      ORDER BY le.charttime, le.labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE
    le.itemid = 51003  -- Troponin T
    AND le.valuenum IS NOT NULL  -- Ensure numeric value
    AND le.hadm_id IN (SELECT hadm_id FROM cohort)
),
cohort_troponin AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    ft.troponin_value,
    CASE
      WHEN ft.troponin_value <= 0.04 THEN 'Normal'
      WHEN ft.troponin_value > 0.04 AND ft.troponin_value <= 0.1 THEN 'Borderline'
      WHEN ft.troponin_value > 0.1 THEN 'Elevated'
    END AS troponin_category
  FROM cohort c
  INNER JOIN first_troponin ft
    ON c.hadm_id = ft.hadm_id
  WHERE
    ft.rn = 1  -- First Troponin measurement
    AND c.age_admit BETWEEN 67 AND 77  -- Age filter
)
SELECT
  troponin_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cohort_troponin), 2) AS percent_of_admissions,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_rate
FROM cohort_troponin
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;