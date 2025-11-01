WITH chest_pain_admissions AS (
  -- Get admissions with chest pain diagnosis for males aged 39-49
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'R07.%') OR
      (d.icd_version = 9 AND d.icd_code LIKE '786.5%')
    )
),

first_hsTnT AS (
  -- Get first hs-TnT measurement for each admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    chest_pain_admissions cpa
    ON le.subject_id = cpa.subject_id AND le.hadm_id = cpa.hadm_id
  WHERE
    le.itemid = 50931  -- hs-TnT
    AND le.valuenum IS NOT NULL
),

hsTnT_categorized AS (
  -- Categorize hs-TnT values
  SELECT
    CASE
      WHEN valuenum < 14 THEN 'Normal (<14 ng/L)'
      WHEN valuenum BETWEEN 14 AND 50 THEN 'Borderline (14-50 ng/L)'
      WHEN valuenum > 50 THEN 'Myocardial injury (>50 ng/L)'
      ELSE 'Unknown'
    END AS hsTnT_category,
    valuenum
  FROM
    first_hsTnT
  WHERE
    rn = 1  -- Only first measurement per admission
)

SELECT
  hsTnT_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 2) AS mean_hsTnT,
  ROUND(PERCENTILE_CONT(valuenum, 0.5) OVER (PARTITION BY hsTnT_category), 2) AS median_hsTnT,
  ROUND(PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY hsTnT_category), 2) AS q1_hsTnT,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY hsTnT_category), 2) AS q3_hsTnT,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY hsTnT_category) -
        PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY hsTnT_category), 2) AS iqr_hsTnT
FROM
  hsTnT_categorized
GROUP BY
  hsTnT_category, valuenum
ORDER BY
  CASE hsTnT_category
    WHEN 'Normal (<14 ng/L)' THEN 1
    WHEN 'Borderline (14-50 ng/L)' THEN 2
    WHEN 'Myocardial injury (>50 ng/L)' THEN 3
    ELSE 4
  END;