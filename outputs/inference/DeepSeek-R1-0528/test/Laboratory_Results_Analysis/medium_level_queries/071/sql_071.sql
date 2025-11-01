WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    -- Compute age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    -- Filter for ACS diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '410%') OR
          (diag.icd_version = 9 AND diag.icd_code LIKE '411%') OR
          (diag.icd_version = 9 AND diag.icd_code LIKE '413%') OR
          (diag.icd_version = 10 AND (
            diag.icd_code LIKE 'I21%' OR 
            diag.icd_code LIKE 'I22%' OR 
            diag.icd_code = 'I20.0' OR 
            diag.icd_code = 'I24.9'
          ))
        )
    )
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 43 AND 53
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (
      PARTITION BY le.subject_id, le.hadm_id
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.itemid = 51003  -- Troponin T
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
categorized AS (
  SELECT
    fc.subject_id,
    fc.hadm_id,
    fc.admittime,
    fc.dischtime,
    ft.valuenum,
    ft.ref_range_upper,
    CASE
      WHEN ft.valuenum <= ft.ref_range_upper THEN 'Normal'
      WHEN ft.valuenum <= ft.ref_range_upper * 1.5 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM filtered_cohort fc
  INNER JOIN first_troponin ft
    ON fc.subject_id = ft.subject_id
    AND fc.hadm_id = ft.hadm_id
    AND ft.rn = 1  -- First Troponin T result
)
SELECT
  troponin_category,
  COUNT(hadm_id) AS count_admissions,
  ROUND(COUNT(hadm_id) * 100.0 / (SELECT COUNT(hadm_id) FROM categorized), 2) AS percentage,
  ROUND(AVG(DATETIME_DIFF(dischtime, admittime, DAY)), 2) AS avg_los_days
FROM categorized
GROUP BY troponin_category
ORDER BY troponin_category;