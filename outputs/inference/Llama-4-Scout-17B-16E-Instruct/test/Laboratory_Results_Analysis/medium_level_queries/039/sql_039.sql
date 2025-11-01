WITH 
  -- Filter patients and admissions
  patients_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 87 AND 97
      AND a.admission_type = 'Emergency'
      AND a.discharge_location LIKE '%chest pain%'
  ),

  -- Extract hs-TnT lab results
  hs_tnt_labs AS (
    SELECT 
      la.subject_id,
      la.hadm_id,
      la.charttime,
      la.valuenum,
      la.valueuom
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` la
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON 
      la.itemid = dl.itemid
    WHERE 
      dl.label = 'High sensitivity troponin T'
      AND la.valuenum IS NOT NULL
  ),

  -- Categorize hs-TnT lab results
  categorized_hs_tnt AS (
    SELECT 
      subject_id,
      hadm_id,
      valuenum,
      CASE 
        WHEN valuenum <= 0.04 THEN 'Normal'
        WHEN valuenum BETWEEN 0.04 AND 0.1 THEN 'Borderline'
        ELSE 'Injury'
      END AS category
    FROM 
      hs_tnt_labs
  ),

  -- Join patients, admissions, and categorized hs-TnT
  final_data AS (
    SELECT 
      pa.subject_id,
      pa.hadm_id,
      pa.anchor_age,
      pa.gender,
      ch.category,
      ch.valuenum
    FROM 
      patients_admissions pa
    JOIN 
      categorized_hs_tnt ch
    ON 
      pa.subject_id = ch.subject_id
      AND pa.hadm_id = ch.hadm_id
    WHERE 
      pa.admittime IS NOT NULL
  )

-- Calculate counts, percentages, and mean, median, IQR of index hs-TnT by category
SELECT 
  category,
  COUNT(DISTINCT hadm_id) AS count,
  COUNT(DISTINCT hadm_id) / SUM(COUNT(DISTINCT hadm_id)) OVER () AS percentage,
  AVG(valuenum) AS mean,
  APPROX_QUANTILES(valuenum, 5)[OFFSET(2)] AS median,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr
FROM 
  final_data
GROUP BY 
  category;