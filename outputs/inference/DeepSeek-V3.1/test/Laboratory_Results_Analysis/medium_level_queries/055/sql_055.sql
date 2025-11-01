WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 81 AND 91
    AND pat.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = adm.hadm_id
        AND (
          (dx.icd_code = 'R079' AND dx.icd_version = 10)  -- Chest pain
          OR (dx.icd_code LIKE 'I21%' AND dx.icd_version = 10)  -- AMI
        )
    )
),
first_troponin AS (
  SELECT 
    lab.hadm_id,
    MIN(lab.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN cohort 
    ON lab.hadm_id = cohort.hadm_id
  WHERE lab.itemid = 50911  -- hs-TnT
  GROUP BY lab.hadm_id
),
troponin_values AS (
  SELECT 
    ft.hadm_id,
    lab.valuenum AS troponin_value,
    CASE 
      WHEN lab.valuenum <= 14 THEN 'Normal'
      WHEN lab.valuenum <= 52 THEN 'Borderline'
      ELSE 'Myocardial injury'
    END AS troponin_category
  FROM first_troponin ft
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON ft.hadm_id = lab.hadm_id 
      AND ft.first_charttime = lab.charttime
      AND lab.itemid = 50911
  WHERE lab.valuenum IS NOT NULL
)
SELECT 
  tv.troponin_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  ROUND(AVG(cohort.los_days), 2) AS mean_los_days
FROM cohort
INNER JOIN troponin_values tv
  ON cohort.hadm_id = tv.hadm_id
GROUP BY tv.troponin_category
ORDER BY 
  CASE tv.troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;