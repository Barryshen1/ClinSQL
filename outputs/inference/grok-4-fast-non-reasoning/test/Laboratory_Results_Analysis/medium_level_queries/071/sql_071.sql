WITH cohort AS (
  -- Base cohort: female patients 43-53 with suspected ACS admission
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(icd.long_title) LIKE '%acute myocardial infarction%'
),
total_cohort AS (
  SELECT COUNT(*) AS total_n
  FROM cohort
),
troponin_initial AS (
  -- Earliest Troponin T per patient/admission within 24h of admission, unit ng/mL
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn  -- Earliest per admission
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN cohort c
    ON le.subject_id = c.subject_id
    AND le.hadm_id = c.hadm_id  -- Restrict to ACS admission
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
    AND le.subject_id = a.subject_id
  WHERE li.label = 'Troponin T'
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= a.admittime
    AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
  QUALIFY rn = 1
),
categorized AS (
  -- Categorize initial Troponin T
  SELECT 
    ti.subject_id,
    ti.hadm_id,
    CASE 
      WHEN ti.valuenum <= 0.01 THEN 'Normal'
      WHEN ti.valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM troponin_initial ti
)
-- Aggregations
SELECT 
  troponin_category,
  COUNT(*) AS n,
  ROUND(COUNT(*) * 100.0 / (SELECT total_n FROM total_cohort), 1) AS percentage,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)), 1) AS avg_hospital_los_days
FROM categorized c
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON c.subject_id = a.subject_id
  AND c.hadm_id = a.hadm_id  -- Match to the admission with the initial Troponin
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;