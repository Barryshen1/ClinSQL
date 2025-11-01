WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%' AND LOWER(label) LIKE '%t%'
),

-- 2) First Troponin-T measurement per admission
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
),

-- 3) Keep only the initial Troponin-T per admission
initial_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    valueuom
  FROM first_troponin
  WHERE rn = 1
),

-- 4) Build the ACS-ACS cohort with age-at-admission and gender filters
cohort AS (
  SELECT
    it.subject_id,
    it.hadm_id,
    it.charttime,
    it.valuenum,
    it.valueuom,
    a.admittime,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM initial_troponin it
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = it.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  WHERE
    (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I24%')
    AND p.gender IN ('M','Male')
),

-- 5) Classify Troponin-T into Normal/Borderline/Elevated
categorized AS (
  SELECT
    CASE
      WHEN LOWER(valueuom) LIKE '%ng/l%' THEN
        CASE
          WHEN valuenum <= 14 THEN 'Normal'
          WHEN valuenum <= 52 THEN 'Borderline'
          ELSE 'Elevated'
        END
      WHEN LOWER(valueuom) LIKE '%ng/ml%' THEN
        CASE
          WHEN valuenum <= 0.014 THEN 'Normal'
          WHEN valuenum <= 0.052 THEN 'Borderline'
          ELSE 'Elevated'
        END
      ELSE NULL -- unknown/unsupported units
    END AS category
  FROM cohort
)

-- 6) Compute counts and percentages (exclude unknown categories)
, total AS (
  SELECT COUNT(*) AS total
  FROM categorized
  WHERE category IS NOT NULL
)

SELECT
  category AS troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / t.total, 1) AS percent
FROM categorized c
CROSS JOIN total t
WHERE c.category IS NOT NULL
GROUP BY category, t.total
ORDER BY category;