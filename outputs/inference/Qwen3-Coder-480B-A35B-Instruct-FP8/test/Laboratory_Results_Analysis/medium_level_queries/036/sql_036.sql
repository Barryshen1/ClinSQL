WITH ami_admissions AS (
  -- Identify admissions with primary AMI diagnosis
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),

eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    ami_admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),

first_hstnt AS (
  -- Get first hs-TnT value within 24 hours of admission
  SELECT
    l.hadm_id,
    l.valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON l.hadm_id = adm.hadm_id
  WHERE
    LOWER(d.label) LIKE '%troponin t%high%sens%'
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
    AND l.hadm_id IN (SELECT hadm_id FROM eligible_patients)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),

categorized AS (
  -- Categorize hs-TnT values
  SELECT
    hadm_id,
    CASE
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum BETWEEN 14 AND 19 THEN 'Borderline'
      WHEN valuenum >= 20 THEN 'Myocardial Injury'
      ELSE 'Other'
    END AS category
  FROM
    first_hstnt
)

-- Final aggregation
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  categorized
GROUP BY
  category
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;