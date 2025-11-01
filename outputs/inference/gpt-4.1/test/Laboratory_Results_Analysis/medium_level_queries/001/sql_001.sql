WITH ami_admissions AS (
  -- Identify admissions for female patients aged 40-50 with AMI
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS adm
    INNER JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND diag.seq_num = 1
    AND (
      -- ICD-10 AMI: I21.x, I22.x; ICD-9 AMI: 410.x, 411.1
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '410%' OR diag.icd_code = '4111'
      ))
      OR
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'
      ))
    )
),

troponin_t_items AS (
  -- Get itemids for Troponin T
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin t%'
),

initial_troponin AS (
  -- Get initial Troponin T value per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
    INNER JOIN troponin_t_items AS tti
      ON l.itemid = tti.itemid
    INNER JOIN ami_admissions AS ami
      ON l.subject_id = ami.subject_id AND l.hadm_id = ami.hadm_id
  WHERE
    l.valuenum IS NOT NULL
),
first_troponin AS (
  -- Select the earliest Troponin T value per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    valueuom,
    ref_range_lower,
    ref_range_upper
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM initial_troponin
  )
  WHERE rn = 1
),

categorized_troponin AS (
  -- Categorize initial Troponin T value
  SELECT
    hadm_id,
    valuenum,
    valueuom,
    ref_range_lower,
    ref_range_upper,
    CASE
      -- Use reference ranges if available
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL THEN
        CASE
          WHEN valuenum < ref_range_lower THEN 'normal'
          WHEN valuenum >= ref_range_lower AND valuenum <= ref_range_upper THEN 'borderline'
          WHEN valuenum > ref_range_upper THEN 'elevated'
          ELSE 'unknown'
        END
      -- Otherwise, use clinical cutoffs (ng/mL)
      WHEN valueuom = 'ng/mL' THEN
        CASE
          WHEN valuenum < 0.01 THEN 'normal'
          WHEN valuenum >= 0.01 AND valuenum <= 0.03 THEN 'borderline'
          WHEN valuenum > 0.03 THEN 'elevated'
          ELSE 'unknown'
        END
      -- Otherwise, use clinical cutoffs (ug/L, equivalent to ng/mL)
      WHEN valueuom = 'ug/L' THEN
        CASE
          WHEN valuenum < 0.01 THEN 'normal'
          WHEN valuenum >= 0.01 AND valuenum <= 0.03 THEN 'borderline'
          WHEN valuenum > 0.03 THEN 'elevated'
          ELSE 'unknown'
        END
      ELSE 'unknown'
    END AS troponin_category
  FROM first_troponin
)

SELECT
  troponin_category,
  COUNT(*) AS initial_troponin_count
FROM categorized_troponin
GROUP BY troponin_category
ORDER BY troponin_category;