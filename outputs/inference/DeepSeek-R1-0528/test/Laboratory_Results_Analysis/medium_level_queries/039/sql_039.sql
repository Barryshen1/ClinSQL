WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    pat.anchor_year,
    pat.anchor_age,
    pat.gender,
    (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE
        diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '786.5%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'R07%')
        )
    )
),
filtered_cohort AS (
  SELECT
    subject_id,
    hadm_id
  FROM cohort
  WHERE age_at_admission BETWEEN 87 AND 97
),
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN filtered_cohort c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE
    l.itemid = 51003  -- hs-TnT
    AND l.valuenum IS NOT NULL  -- Ensure numeric value exists
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.subject_id, l.hadm_id
    ORDER BY l.charttime, l.labevent_id
  ) = 1  -- First troponin per admission
),
categorized AS (
  SELECT
    hadm_id,
    troponin_value,
    CASE
      WHEN troponin_value <= 0.04 THEN 'Normal'
      WHEN troponin_value > 0.04 AND troponin_value <= 0.1 THEN 'Borderline'
      WHEN troponin_value > 0.1 THEN 'Injury'
    END AS category
  FROM first_troponin
)
SELECT
  category,
  COUNT(hadm_id) AS n,
  ROUND(COUNT(hadm_id) * 100.0 / (SELECT COUNT(*) FROM categorized), 2) AS percentage,
  ROUND(AVG(troponin_value), 3) AS mean,
  ROUND(APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)], 3) AS median,
  ROUND(APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] - APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)], 3) AS iqr
FROM categorized
GROUP BY category
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
  END;