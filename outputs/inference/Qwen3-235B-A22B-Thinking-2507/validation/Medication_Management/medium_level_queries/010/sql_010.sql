WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.hadm_id = a.hadm_id
        AND d1.icd_code LIKE 'E11%'
        AND d1.icd_version = 10
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND d2.icd_code LIKE 'I50%'
        AND d2.icd_version = 10
    )
),

medications AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    CASE WHEN p.drug LIKE '%metformin%' THEN 1 ELSE 0 END AS met,
    CASE WHEN p.drug LIKE '%glipizide%' OR p.drug LIKE '%glyburide%' OR p.drug LIKE '%glimepiride%' THEN 1 ELSE 0 END AS su,
    CASE WHEN p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%saxagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' THEN 1 ELSE 0 END AS dpp4,
    CASE WHEN p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' OR p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%ertugliflozin%' THEN 1 ELSE 0 END AS sglt2,
    CASE WHEN p.drug LIKE '%exenatide%' OR p.drug LIKE '%liraglutide%' OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%semaglutide%' THEN 1 ELSE 0 END AS glp1,
    CASE WHEN p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' THEN 1 ELSE 0 END AS tzd,
    CASE WHEN p.drug LIKE '%insulin%' THEN 1 ELSE 0 END AS insulin
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL
),

first_admin AS (
  SELECT 
    hadm_id,
    MIN(CASE WHEN met = 1 THEN starttime ELSE NULL END) AS first_met,
    MIN(CASE WHEN su = 1 THEN starttime ELSE NULL END) AS first_su,
    MIN(CASE WHEN dpp4 = 1 THEN starttime ELSE NULL END) AS first_dpp4,
    MIN(CASE WHEN sglt2 = 1 THEN starttime ELSE NULL END) AS first_sglt2,
    MIN(CASE WHEN glp1 = 1 THEN starttime ELSE NULL END) AS first_glp1,
    MIN(CASE WHEN tzd = 1 THEN starttime ELSE NULL END) AS first_tzd,
    MIN(CASE WHEN insulin = 1 THEN starttime ELSE NULL END) AS first_insulin
  FROM medications
  GROUP BY hadm_id
),

classes AS (
  SELECT 'met' AS drug_class
  UNION ALL SELECT 'su'
  UNION ALL SELECT 'dpp4'
  UNION ALL SELECT 'sglt2'
  UNION ALL SELECT 'glp1'
  UNION ALL SELECT 'tzd'
  UNION ALL SELECT 'insulin'
),

totals AS (
  SELECT COUNT(*) AS total_cohort FROM cohort
)

SELECT 
  c.drug_class,
  count_first12h,
  count_final48h,
  total_cohort,
  ROUND(count_first12h * 100.0 / total_cohort, 2) AS pct_first12h,
  ROUND(count_final48h * 100.0 / total_cohort, 2) AS pct_final48h,
  ROUND((count_final48h * 100.0 / total_cohort) - (count_first12h * 100.0 / total_cohort), 2) AS net_change
FROM (
  SELECT 
    'met' AS drug_class,
    SUM(CASE WHEN first_met >= admittime AND first_met <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS count_first12h,
    SUM(CASE WHEN first_met >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_met <= dischtime THEN 1 ELSE 0 END) AS count_final48h
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
  UNION ALL
  SELECT 
    'su',
    SUM(CASE WHEN first_su >= admittime AND first_su <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END),
    SUM(CASE WHEN first_su >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_su <= dischtime THEN 1 ELSE 0 END)
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
  UNION ALL
  SELECT 
    'dpp4',
    SUM(CASE WHEN first_dpp4 >= admittime AND first_dpp4 <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END),
    SUM(CASE WHEN first_dpp4 >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_dpp4 <= dischtime THEN 1 ELSE 0 END)
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
  UNION ALL
  SELECT 
    'sglt2',
    SUM(CASE WHEN first_sglt2 >= admittime AND first_sglt2 <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END),
    SUM(CASE WHEN first_sglt2 >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_sglt2 <= dischtime THEN 1 ELSE 0 END)
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
  UNION ALL
  SELECT 
    'glp1',
    SUM(CASE WHEN first_glp1 >= admittime AND first_glp1 <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END),
    SUM(CASE WHEN first_glp1 >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_glp1 <= dischtime THEN 1 ELSE 0 END)
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
  UNION ALL
  SELECT 
    'tzd',
    SUM(CASE WHEN first_tzd >= admittime AND first_tzd <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END),
    SUM(CASE WHEN first_tzd >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_tzd <= dischtime THEN 1 ELSE 0 END)
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
  UNION ALL
  SELECT 
    'insulin',
    SUM(CASE WHEN first_insulin >= admittime AND first_insulin <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END),
    SUM(CASE WHEN first_insulin >= GREATEST(TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR), admittime) AND first_insulin <= dischtime THEN 1 ELSE 0 END)
  FROM cohort
  LEFT JOIN first_admin USING (hadm_id)
) counts
CROSS JOIN totals
JOIN classes c ON counts.drug_class = c.drug_class
ORDER BY drug_class;