WITH cohort AS (
  -- Identify admissions for males aged 43-53 with AMI (primary vs secondary)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN MIN(CASE WHEN d.seq_num = 1 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%') THEN 1 END) = 1 
      THEN 'Primary' 
      ELSE 'Secondary' 
    END AS ami_type,
    CASE 
      WHEN EXTRACT(DAY FROM TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN EXTRACT(DAY FROM TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    AND EXTRACT(DAY FROM TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) BETWEEN 1 AND 7  -- Focus on 1-7 days
  GROUP BY 
    p.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING los_category IS NOT NULL  -- Exclude any that don't fit 1-3 or 4-7
),
imaging_counts AS (
  -- Count distinct radiography/CT events per admission (using common itemids)
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT ce.charttime) AS num_imaging
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.hadm_id = ce.hadm_id
  WHERE 
    ce.itemid IN (
      220045,  -- Chest X-ray
      220044,  -- CT head
      220179,  -- CT chest
      220180,  -- CT abdomen
      220181,  -- CT pelvis
      220182,  -- CT chest/abdomen/pelvis
      220258,  -- X-ray other
      228139,  -- Ultrasound
      228161,  -- MRI head
      228162,  -- MRI other
      228164,  -- Nuclear medicine
      228165,  -- PET scan
      228166,  -- SPECT
      228167,  -- Echocardiogram
      228168,  -- Vascular ultrasound
      228169,  -- Fluoroscopy
      228170,  -- Mammography (if relevant)
      228171,  -- DEXA scan
      220210,  -- Portable X-ray
      220232   -- Radiograph
    )
    AND ce.charttime >= c.admittime
    AND ce.charttime <= c.dischtime
  GROUP BY 
    c.hadm_id
)
-- Aggregate medians and IQR by LOS and AMI type
SELECT 
  los_category,
  ami_type,
  COUNT(*) AS num_admissions,
  (SELECT q[OFFSET(2)] FROM UNNEST(APPROX_QUANTILES(COALESCE(ic.num_imaging, 0), 4)) AS q) AS median_imaging,
  (SELECT q[OFFSET(1)] FROM UNNEST(APPROX_QUANTILES(COALESCE(ic.num_imaging, 0), 4)) AS q) AS iqr_q1,
  (SELECT q[OFFSET(3)] FROM UNNEST(APPROX_QUANTILES(COALESCE(ic.num_imaging, 0), 4)) AS q) AS iqr_q3
FROM 
  cohort c
LEFT JOIN 
  imaging_counts ic ON c.hadm_id = ic.hadm_id
GROUP BY 
  los_category, ami_type
ORDER BY 
  los_category, ami_type;