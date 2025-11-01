WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE 
        d1.subject_id = a.subject_id 
        AND d1.hadm_id = a.hadm_id 
        AND d1.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE 
        d2.subject_id = a.subject_id 
        AND d2.hadm_id = a.hadm_id 
        AND d2.icd_code LIKE 'I50%'
    )
),

insulin_prescriptions AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
      WHEN p.drug LIKE '%Insulin%' 
        AND p.route IN ('Subcutaneous', 'SC', 'IV')
        AND p.starttime <= c.admittime + INTERVAL '24' HOUR
        AND p.stoptime >= c.admittime 
      THEN 1 ELSE 0 
    END) AS insulin_first24,
    MAX(CASE 
      WHEN p.drug LIKE '%Insulin%' 
        AND p.route IN ('Subcutaneous', 'SC', 'IV')
        AND p.starttime <= c.dischtime
        AND p.stoptime >= c.dischtime - INTERVAL '48' HOUR 
      THEN 1 ELSE 0 
    END) AS insulin_last48
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
),

oral_prescriptions AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
      WHEN p.route = 'Oral'
        AND p.drug IN (
          'Metformin', 'Glipizide', 'Glyburide', 'Pioglitazone', 
          'Rosiglitazone', 'Sitagliptin', 'Linagliptin', 'Dapagliflozin', 
          'Empagliflozin', 'Canagliflozin', 'Acarbose', 'Miglitol', 
          'Tolbutamide', 'Chlorpropamide'
        )
        AND p.starttime <= c.admittime + INTERVAL '24' HOUR
        AND p.stoptime >= c.admittime 
      THEN 1 ELSE 0 
    END) AS oral_first24,
    MAX(CASE 
      WHEN p.route = 'Oral'
        AND p.drug IN (
          'Metformin', 'Glipizide', 'Glyburide', 'Pioglitazone', 
          'Rosiglitazone', 'Sitagliptin', 'Linagliptin', 'Dapagliflozin', 
          'Empagliflozin', 'Canagliflozin', 'Acarbose', 'Miglitol', 
          'Tolbutamide', 'Chlorpropamide'
        )
        AND p.starttime <= c.dischtime
        AND p.stoptime >= c.dischtime - INTERVAL '48' HOUR 
      THEN 1 ELSE 0 
    END) AS oral_last48
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
)

SELECT 
  'Insulin' AS drug_type,
  AVG(COALESCE(i.insulin_first24, 0)) * 100 AS first24_prevalence,
  AVG(COALESCE(i.insulin_last48, 0)) * 100 AS last48_prevalence,
  SUM(CASE WHEN i.insulin_first24 = 1 AND i.insulin_last48 = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN i.insulin_first24 = 0 AND i.insulin_last48 = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN i.insulin_first24 = 1 AND i.insulin_last48 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM cohort c
LEFT JOIN insulin_prescriptions i ON c.hadm_id = i.hadm_id

UNION ALL

SELECT 
  'Oral Agents' AS drug_type,
  AVG(COALESCE(o.oral_first24, 0)) * 100 AS first24_prevalence,
  AVG(COALESCE(o.oral_last48, 0)) * 100 AS last48_prevalence,
  SUM(CASE WHEN o.oral_first24 = 1 AND o.oral_last48 = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN o.oral_first24 = 0 AND o.oral_last48 = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN o.oral_first24 = 1 AND o.oral_last48 = 0 THEN 1 ELSE 0 END) AS discontinued
FROM cohort c
LEFT JOIN oral_prescriptions o ON c.hadm_id = o.hadm_id;